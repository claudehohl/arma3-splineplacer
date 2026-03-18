/*
    SP_fnc_getWaypoints
    Collects all SP_Waypoint objects belonging to a specific spline group,
    sorted by their Eden variable name (alphabetical / numeric order).

    Parameters:
        _prefix - String: the spline group prefix (e.g. "s1", "road")

    Returns:
        Array of Eden entity objects, sorted by name.
        Empty array if fewer than 2 found in this prefix group.
*/

params ["_prefix"];

private _pattern = format ["^%1_\d+$", _prefix];
private _waypoints = (allMissionObjects "SP_Waypoint") select {
    ((_x get3DENAttribute "name") select 0) regexMatch _pattern
};

if (count _waypoints < 2) exitWith { [] };

private _named = _waypoints apply {
    private _name = (_x get3DENAttribute "name") select 0;
    [_name, _x]
};
_named sort true;

_named apply { _x select 1 }
