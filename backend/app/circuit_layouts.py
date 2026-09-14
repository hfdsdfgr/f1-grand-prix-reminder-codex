from app.models import CircuitLayout


_SOURCE = 'https://github.com/f1db/f1db/tree/main/src/assets/circuits'
_LAYOUTS = {
    'baku': ('baku-1', 2016, 20),
    'marina_bay': ('marina-bay-4', 2023, 19),
    'suzuka': ('suzuka-2', 2022, 18),
}


def circuit_layout(external_id: str | None, season: int) -> CircuitLayout | None:
    value = _LAYOUTS.get(external_id or '')
    if value is None or season < value[1]:
        return None
    layout_id, valid_from, turns = value
    return CircuitLayout(
        id=layout_id,
        asset_path=f'assets/circuits/{layout_id}.svg',
        valid_from=valid_from,
        turns=turns,
        source=_SOURCE,
        license='CC BY 4.0',
    )
