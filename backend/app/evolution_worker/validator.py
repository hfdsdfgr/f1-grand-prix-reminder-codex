import re

from app.evolution_worker.models import (
    EvidenceLevel, EvolutionExtraction, ExtractionBatch, UpgradeStatus, ValidatedBatch,
)


def _normalized(value: str) -> str:
    return re.sub(r'\s+', ' ', value).strip().casefold()


def validate_batch(batch: ExtractionBatch, documents) -> ValidatedBatch:
    sources = {item.source_id: item for item in documents}
    race_ids = {item.race_id for item in documents}
    results: list[EvolutionExtraction] = []
    issues: list[str] = []
    for result in batch.results:
        if result.race_id not in race_ids:
            issues.append(f'{result.team_id}: discarded result for unexpected race {result.race_id}')
            continue
        accepted = []
        for index, update in enumerate(result.updates):
            prefix = f'{result.team_id}/{update.component_id}/{index}'
            source_ids = list(dict.fromkeys(item for item in update.source_ids if item in sources))
            evidence = []
            supported: set[str] = set()
            for item in update.evidence:
                source = sources.get(item.source_id)
                if (source and item.source_id in source_ids
                        and _normalized(item.quote) in _normalized(source.cleaned_text)):
                    evidence.append(item)
                    supported.update(item.supports)
                else:
                    issues.append(f'{prefix}: discarded unverifiable quote')
            if not source_ids or 'change' not in supported:
                issues.append(f'{prefix}: discarded update without sourced change evidence')
                continue
            goal = update.goal if 'goal' in supported else None
            effect = update.expected_effect if 'expected_effect' in supported else None
            if update.goal and goal is None:
                issues.append(f'{prefix}: removed unsupported goal')
            if update.expected_effect and effect is None:
                issues.append(f'{prefix}: removed unsupported expected_effect')
            feedback = update.driver_feedback if 'driver_feedback' in supported else []
            feedback = [item for item in feedback if item.source_ids
                        and all(source_id in source_ids for source_id in item.source_ids)]
            if update.driver_feedback and not feedback:
                issues.append(f'{prefix}: removed unsupported driver feedback')
            status = update.status if 'status' in supported else UpgradeStatus.UNKNOWN
            quotes = ' '.join(item.quote.casefold() for item in evidence if 'status' in item.supports)
            if status in {UpgradeStatus.INTRODUCED, UpgradeStatus.RETAINED} and re.search(
                r'\b(test|tested|testing|trial|evaluate|evaluation)\b', quotes,
            ) and not re.search(r'\b(introduced|retained|raced|used in the race)\b', quotes):
                status = UpgradeStatus.TESTED
                issues.append(f'{prefix}: downgraded adoption claim to tested')
            tiers = [sources[source_id].source_tier for source_id in source_ids]
            official = any(tier <= 3 for tier in tiers)
            level = EvidenceLevel.CONFIRMED if official else (
                EvidenceLevel.OBSERVED if len(source_ids) > 1 else EvidenceLevel.REPORTED
            )
            confidence = .55 + (.20 if official else .05) + min(.10, .05 * (len(source_ids) - 1))
            if status == UpgradeStatus.UNKNOWN:
                confidence -= .10
            if not goal and not effect:
                confidence -= .05
            accepted.append(update.model_copy(update={
                'source_ids': source_ids, 'evidence': evidence, 'goal': goal,
                'expected_effect': effect, 'status': status, 'evidence_level': level,
                'driver_feedback': feedback,
                'confidence': round(max(0.0, min(1.0, confidence)), 2),
            }))
        results.append(result.model_copy(update={'updates': accepted}))
    return ValidatedBatch(results=results, issues=issues)
