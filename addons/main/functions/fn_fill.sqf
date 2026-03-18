params ["_prefix", "_state", ["_snapGround", false]];

private _waypoints = [_prefix] call SP_fnc_getWaypoints;
if (count _waypoints < 2) exitWith {};

private _spacing    = 0; // resolved below
private _alignToDir = SP_settings get "alignToDir";
private _resolution = SP_settings get "resolution";

// ── Reference object ──────────────────────────────────────────────────────────
private _refObj = _state getOrDefault ["cachedRefObj", objNull];

if (isNull _refObj) then {
    {
        private _candidates = (get3DENConnections _x) select { _x isEqualType [] };
        _candidates = (_candidates select { (_x select 0) == "Sync" && (_x select 1) isEqualType objNull }) apply { _x select 1 };
        _candidates = _candidates select { !(typeOf _x in SP_waypointClasses) && !isNull _x && typeOf _x != "" && typeOf _x != "EMPTY" };
        if (_candidates isNotEqualTo []) exitWith { _refObj = _candidates select 0; };
    } forEach _waypoints;
};

if (typeOf _refObj == "" || typeOf _refObj == "EMPTY") then { _refObj = objNull; };

// ── Distance object (optional, sync'd to ref obj) ─────────────────────────────
private _distObj = objNull;
if (!isNull _refObj) then {
    private _synced = (get3DENConnections _refObj) select { _x isEqualType [] };
    _synced = (_synced select { (_x select 0) == "Sync" && (_x select 1) isEqualType objNull }) apply { _x select 1 };
    { if (!(typeOf _x in SP_waypointClasses) && !isNull _x && typeOf _x != "" && typeOf _x != "EMPTY") exitWith { _distObj = _x; }; } forEach _synced;
};
_spacing = if (!isNull _distObj) then {
    (_refObj distance _distObj) max 0.1
} else {
    (SP_settings get "spacing") max 0.1
};

private _class = if (!isNull _refObj) then { typeOf _refObj } else { SP_settings get "classname" };
if (_class == "" || _class == "EMPTY") then {
    _class = SP_settings get "classname";
    if (_class == "" || _class == "EMPTY") exitWith {};
};
private _refDir = if (!isNull _refObj) then { getDir _refObj } else { 0 };

private _controlPoints = _waypoints apply { (getPosASL _x) vectorAdd [0,0,-5] };
private _samples = [_controlPoints, _spacing, _resolution] call SP_fnc_sampleSpline;

if (count _samples == 0) exitWith {};

private _refInit = if (!isNull _refObj) then {
    (_refObj get3DENAttribute "init") select 0
} else { "" };

// ── Incremental update: reuse existing objects, create/delete only the delta ──
private _oldObjects = +(_state getOrDefault ["generatedObjects", []]);
private _oldCount   = count _oldObjects;

// If class changed, all old objects must be replaced
if (_oldCount > 0 && typeOf (_oldObjects select 0) != _class) then {
    delete3DENEntities _oldObjects;
    _oldObjects = [];
    _oldCount   = 0;
};

private _newObjects = [];

{
    private _i       = _forEachIndex;
    private _posASL  = _x select 0;
    private _tangent = _x select 1;
    private _posATL  = ASLToATL _posASL;

    if (_snapGround) then { _posATL set [2, 0]; };

    private _heading = if (_alignToDir) then {
        private _h = (_tangent select 0) atan2 (_tangent select 1);
        if (_h < 0) then { _h = _h + 360 };
        (_h + _refDir + 90) % 360
    } else {
        if (!isNull _refObj) then { _refDir } else { -1 }
    };

    private _pitch = 0;
    private _bank  = 0;
    if (_alignToDir && !_snapGround) then {
        private _hDist = sqrt((_tangent select 0)^2 + (_tangent select 1)^2) max 0.0001;
        private _elevation = (_tangent select 2) atan2 _hDist;
        _pitch = -(_elevation * (_tangent select 1) / _hDist);
        _bank  = _elevation * (_tangent select 0) / _hDist;
    };

    // Reuse existing object if available, otherwise create a new one
    private _entity = if (_i < _oldCount) then {
        _oldObjects select _i
    } else {
        private _e = create3DENEntity ["Object", _class, _posATL];
        if (!isNull _e) then {
            // Tag with name so recovery scan can identify these objects after save/load.
            // (description attribute is NOT serialized to mission.sqm for regular objects)
            private _n = _i + 1;
            private _pad = if (_n < 10) then { "00" } else { ["", "0"] select (_n < 100) };
            _e set3DENAttribute ["name", format ["sp_%1_%2%3", _prefix, _pad, _n]];
            if (_refInit != "") then { _e set3DENAttribute ["init", _refInit]; };
        };
        _e
    };

    if (!isNull _entity) then {
        _entity setPosATL _posATL;
        _entity set3DENAttribute ["position", _posATL];
        if (_heading >= 0) then {
            _entity setDir _heading;
            _entity set3DENAttribute ["rotation", [_pitch, _bank, _heading]];
        };
        _newObjects pushBack _entity;
    };
} forEach _samples;

// Delete any excess old objects
if (_oldCount > count _samples) then {
    delete3DENEntities (_oldObjects select [count _samples, _oldCount - count _samples]);
};

_state set ["generatedObjects", _newObjects];
