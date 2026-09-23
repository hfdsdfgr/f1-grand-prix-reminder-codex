from app.models import CircuitLayout


_SOURCE = 'https://github.com/f1db/f1db/tree/main/src/assets/circuits'
_LAYOUTS = {
    'albert_park': ('melbourne-2', 2022, 14),
    'shanghai': ('shanghai-1', 2004, 16),
    'baku': ('baku-1', 2016, 20),
    'miami': ('miami-1', 2022, 19),
    'villeneuve': ('montreal-6', 2002, 14),
    'monaco': ('monaco-6', 2003, 19),
    'catalunya': ('catalunya-6', 2023, 14),
    'red_bull_ring': ('spielberg-3', 2014, 10),
    'silverstone': ('silverstone-8', 2010, 18),
    'spa': ('spa-francorchamps-4', 2007, 19),
    'hungaroring': ('hungaroring-3', 2003, 14),
    'zandvoort': ('zandvoort-5', 2021, 14),
    'monza': ('monza-7', 2000, 11),
    'madring': ('madring-1', 2026, 22),
    'sepang': ('sepang-1', 1999, 15),
    'marina_bay': ('marina-bay-4', 2023, 19),
    'suzuka': ('suzuka-2', 2022, 18),
    'americas': ('austin-1', 2012, 20),
    'rodriguez': ('mexico-city-3', 2015, 17),
    'interlagos': ('interlagos-2', 1990, 15),
    'vegas': ('las-vegas-1', 2023, 17),
    'losail': ('lusail-1', 2021, 16),
    'yas_marina': ('yas-marina-2', 2021, 16),
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
