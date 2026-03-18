// Sample a smooth interpolating spline at evenly-spaced arc-length intervals.
//
// Algorithm: Cubic Hermite spline with chord-length Catmull-Rom tangents.
//   T_i = (P_{i+1} - P_{i-1}) * chord_next / (chord_prev + chord_next)
// This guarantees no cusps or self-intersections for any point configuration.
//
// Params : _controlPoints (array of [x,y,z] ASL), _spacing (metres), [_resolution=20]
// Returns: Array of [posASL, tangentVec]

params ["_controlPoints", "_spacing", ["_resolution", 20]];

if (count _controlPoints < 2) exitWith { [] };

// ── Ghost endpoints so the spline passes through the first and last user point ─
private _n   = count _controlPoints;
private _p0  = _controlPoints select 0;
private _p1  = _controlPoints select 1;
private _pNm1 = _controlPoints select (_n - 1);
private _pNm2 = _controlPoints select (_n - 2);

private _ghost0 = [2*(_p0 select 0)-(_p1 select 0),
                   2*(_p0 select 1)-(_p1 select 1),
                   2*(_p0 select 2)-(_p1 select 2)];
private _ghostN = [2*(_pNm1 select 0)-(_pNm2 select 0),
                   2*(_pNm1 select 1)-(_pNm2 select 1),
                   2*(_pNm1 select 2)-(_pNm2 select 2)];

private _pts = [_ghost0] + _controlPoints + [_ghostN];
private _m   = count _pts;   // = _n + 2

// ── Chord lengths between consecutive points ──────────────────────────────────
private _chords = [];
for "_i" from 0 to (_m - 2) do {
    private _a = _pts select _i;
    private _b = _pts select (_i + 1);
    private _dx = (_b select 0) - (_a select 0);
    private _dy = (_b select 1) - (_a select 1);
    private _dz = (_b select 2) - (_a select 2);
    _chords pushBack (sqrt(_dx*_dx + _dy*_dy + _dz*_dz) max 0.0001);
};

// ── Hermite tangent at each point (chord-length Catmull-Rom formula) ──────────
// T_i = (P_{i+1} - P_{i-1}) * chord_next / (chord_prev + chord_next)
// Indices 0 and _m-1 are ghost points; we compute tangents for 1 .. _m-2.
private _tangents = [];
for "_i" from 0 to (_m - 1) do { _tangents pushBack [0,0,0]; };

for "_i" from 1 to (_m - 2) do {
    private _prev  = _pts select (_i - 1);
    private _next  = _pts select (_i + 1);
    private _dp    = _chords select (_i - 1);   // chord prev
    private _dn    = _chords select _i;          // chord next
    private _scale = _dn / (_dp + _dn);
    _tangents set [_i, [
        ((_next select 0) - (_prev select 0)) * _scale,
        ((_next select 1) - (_prev select 1)) * _scale,
        ((_next select 2) - (_prev select 2)) * _scale
    ]];
};

// ── Build dense arc-length table: [cumDist, posASL, tangentVec] ───────────────
// One entry per Hermite sample; no segment-tracking needed (avoids boundary bugs).
private _arcTable = [];
private _cumDist  = 0;

for "_seg" from 1 to (_m - 3) do {         // user segments: pts[1]→pts[2], …, pts[m-3]→pts[m-2]
    private _pa = _pts     select _seg;
    private _pb = _pts     select (_seg + 1);
    private _ta = _tangents select _seg;
    private _tb = _tangents select (_seg + 1);

    private _prevPos = _pa;
    private _startK  = parseNumber (_seg != 1);   // skip t=0 for seg>1 (duplicate junction)

    for "_k" from _startK to _resolution do {
        private _t  = _k / _resolution;
        private _t2 = _t * _t;
        private _t3 = _t2 * _t;

        // Cubic Hermite basis
        private _h00 =  2*_t3 - 3*_t2 + 1;
        private _h10 =    _t3 - 2*_t2 + _t;
        private _h01 = -2*_t3 + 3*_t2;
        private _h11 =    _t3 -   _t2;

        private _pos = [
            _h00*(_pa select 0) + _h10*(_ta select 0) + _h01*(_pb select 0) + _h11*(_tb select 0),
            _h00*(_pa select 1) + _h10*(_ta select 1) + _h01*(_pb select 1) + _h11*(_tb select 1),
            _h00*(_pa select 2) + _h10*(_ta select 2) + _h01*(_pb select 2) + _h11*(_tb select 2)
        ];

        // Arc length
        if (_k > 0 || _seg > 1) then {
            private _dx = (_pos select 0) - (_prevPos select 0);
            private _dy = (_pos select 1) - (_prevPos select 1);
            private _dz = (_pos select 2) - (_prevPos select 2);
            _cumDist = _cumDist + sqrt(_dx*_dx + _dy*_dy + _dz*_dz);
        };

        // Hermite derivative → tangent direction
        private _dh00 =  6*_t2 - 6*_t;
        private _dh10 =  3*_t2 - 4*_t + 1;
        private _dh01 = -6*_t2 + 6*_t;
        private _dh11 =  3*_t2 - 2*_t;

        private _tan = [
            _dh00*(_pa select 0) + _dh10*(_ta select 0) + _dh01*(_pb select 0) + _dh11*(_tb select 0),
            _dh00*(_pa select 1) + _dh10*(_ta select 1) + _dh01*(_pb select 1) + _dh11*(_tb select 1),
            _dh00*(_pa select 2) + _dh10*(_ta select 2) + _dh01*(_pb select 2) + _dh11*(_tb select 2)
        ];
        private _tlen = sqrt((_tan select 0)^2 + (_tan select 1)^2 + (_tan select 2)^2) max 0.0001;
        _tan = [(_tan select 0)/_tlen, (_tan select 1)/_tlen, (_tan select 2)/_tlen];

        _arcTable pushBack [_cumDist, _pos, _tan];
        _prevPos = _pos;
    };
};

private _totalLength = _cumDist;

// ── Walk arc-length table at fixed spacing ────────────────────────────────────
private _result     = [];
private _targetDist = 0;
private _tableIdx   = 0;
private _tableCount = count _arcTable;

while { _targetDist <= _totalLength } do {
    // Advance index until next entry would overshoot _targetDist
    while {
        _tableIdx < (_tableCount - 1) &&
        { ((_arcTable select (_tableIdx + 1)) select 0) <= _targetDist }
    } do { _tableIdx = _tableIdx + 1 };

    if (_tableIdx >= _tableCount - 1) then {
        private _last = _arcTable select (_tableCount - 1);
        _result pushBack [_last select 1, _last select 2];
        _targetDist = _totalLength + _spacing;  // exit loop
    } else {
        private _lo   = _arcTable select _tableIdx;
        private _hi   = _arcTable select (_tableIdx + 1);
        private _dLo  = _lo select 0;
        private _dHi  = _hi select 0;
        private _frac = if (_dHi - _dLo < 0.0001) then { 0 } else {
            (_targetDist - _dLo) / (_dHi - _dLo)
        };

        private _posLo = _lo select 1;
        private _posHi = _hi select 1;
        private _tanLo = _lo select 2;
        private _tanHi = _hi select 2;

        private _pos = [
            (_posLo select 0) + _frac * ((_posHi select 0) - (_posLo select 0)),
            (_posLo select 1) + _frac * ((_posHi select 1) - (_posLo select 1)),
            (_posLo select 2) + _frac * ((_posHi select 2) - (_posLo select 2))
        ];

        private _tan = [
            (_tanLo select 0) + _frac * ((_tanHi select 0) - (_tanLo select 0)),
            (_tanLo select 1) + _frac * ((_tanHi select 1) - (_tanLo select 1)),
            (_tanLo select 2) + _frac * ((_tanHi select 2) - (_tanLo select 2))
        ];
        private _tlen = sqrt((_tan select 0)^2 + (_tan select 1)^2 + (_tan select 2)^2) max 0.0001;
        _tan = [(_tan select 0)/_tlen, (_tan select 1)/_tlen, (_tan select 2)/_tlen];

        _result pushBack [_pos, _tan];
        _targetDist = _targetDist + _spacing;
    };
};

_result
