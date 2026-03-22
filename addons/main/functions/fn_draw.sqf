/*
    SP_fnc_draw
    Called every frame via the Draw3D mission event handler.
    - Renders live spline preview for every waypoint group
    - Manages per-group state in SP_splines HashMap
    - Triggers auto-rebuild when waypoint positions, sync, or rotation changes
*/

// Use shared palette from SP_colorPalette (defined in fn_init), with draw-specific alpha
private _palette = SP_colorPalette apply { [_x select 0, _x select 1, _x select 2, 0.85] };

// ── Recover generated objects after Play Scenario (runs once per init cycle) ─
if (!isNil "SP_needsRecovery" && SP_needsRecovery) then {
    SP_needsRecovery = false;
    SP_splines = createHashMap;

    // Re-group recovered objects by prefix encoded in their name tag (sp_<prefix>_NNN).
    // Note: description attribute is NOT serialized to mission.sqm for regular objects,
    // so we use the name attribute as the persistent tag instead.
    {
        private _lbName = (_x get3DENAttribute "name") select 0;
        private _prefix = _lbName regexReplace ["^sp_", ""] regexReplace ["_\d+$", ""];
        if !(_prefix in keys SP_splines) then {
            SP_splines set [_prefix, createHashMap];
        };
        private _state = SP_splines get _prefix;
        private _objs = _state getOrDefault ["generatedObjects", []];
        _objs pushBack _x;
        _state set ["generatedObjects", _objs];
    } forEach (allMissionObjects "" select {
        ((_x get3DENAttribute "name") select 0) regexMatch "^sp_.+_\d+$"
    });

    // Sort each recovered group by numeric suffix so generatedObjects[i]
    // matches spline position i (allMissionObjects returns arbitrary order).
    {
        private _objs = _y getOrDefault ["generatedObjects", []];
        if (count _objs > 1) then {
            private _pairs = _objs apply {
                private _n = (_x get3DENAttribute "name") select 0;
                private _idx = parseNumber (_n regexReplace ["^sp_.+_", ""]);
                [_idx, _x]
            };
            _pairs sort true;
            _y set ["generatedObjects", _pairs apply { _x select 1 }];
        };
    } forEach SP_splines;
};

// ── Collect all SP_Waypoint objects and group by prefix ──────────────────────
private _allWaypoints = allMissionObjects "SP_Waypoint";

// Build HashMap: prefix → [sorted waypoints]
private _groups = createHashMap;
{
    private _name = (_x get3DENAttribute "name") select 0;
    private _prefix = if (_name regexMatch "^.+_\d+$") then {
        _name regexReplace ["_\d+$", ""]
    } else { _name };
    if !(_prefix in keys _groups) then {
        _groups set [_prefix, []];
    };
    (_groups get _prefix) pushBack [_name, _x];
} forEach _allWaypoints;

// Sort each group alphabetically by name
{
    private _list = _y;
    _list sort true;
    _groups set [_x, _list apply { _x select 1 }];
} forEach _groups;

// ── Remove stale groups (prefix no longer has any waypoints) ─────────────────
{
    private _prefix = _x;
    if !(_prefix in keys _groups) then {
        private _state = SP_splines get _prefix;
        private _oldObjs = _state getOrDefault ["generatedObjects", []];
        if (_oldObjs isNotEqualTo []) then {
            delete3DENEntities _oldObjs;
        };
        SP_splines deleteAt _prefix;
    };
} forEach (keys SP_splines);

// ── Process each group ────────────────────────────────────────────────────────
{
    private _prefix     = _x;
    private _waypoints  = _y;
    private _num        = parseNumber (_prefix regexReplace ["^s", ""]);
    private _color      = _palette select ((_num - 1) mod count _palette);
    private _snapGround = (typeOf (_waypoints select 0)) == "SP_WaypointGround";

    if (count _waypoints < 2) then {
        // Only 1 waypoint – draw the lone sphere but skip spline logic
        {
            drawIcon3D [
                "\a3\ui_f\data\map\markers\nato\b_unknown.paa",
                _color,
                ASLToAGL (getPosASL _x),
                0.5, 0.5, 0,
                (_x get3DENAttribute "name") select 0,
                1, 0.03
            ];
        } forEach _waypoints;
    } else {

        // Ensure state entry exists
        if !(_prefix in keys SP_splines) then {
            SP_splines set [_prefix, createHashMap];
        };
        private _state = SP_splines get _prefix;

        // ── Detect reference object (first non-waypoint sync'd to any waypoint) ─
        private _currentRef = objNull;
        {
            private _candidates = (get3DENConnections _x) select { _x isEqualType [] };
            _candidates = (_candidates select { (_x select 0) == "Sync" && (_x select 1) isEqualType objNull }) apply { _x select 1 };
            _candidates = _candidates select {
                !(typeOf _x in SP_waypointClasses) && !isNull _x && typeOf _x != "" && typeOf _x != "EMPTY"
            };
            if (_candidates isNotEqualTo []) exitWith { _currentRef = _candidates select 0; };
        } forEach _waypoints;

        // Clear zombie reference
        private _cachedRef = _state getOrDefault ["cachedRefObj", objNull];
        if (typeOf _cachedRef == "" || typeOf _cachedRef == "EMPTY") then {
            _cachedRef = objNull;
            _state set ["cachedRefObj", objNull];
        };

        private _prevRefDir = _state getOrDefault ["cachedRefDir", 0];
        private _refChanged = (_currentRef isNotEqualTo _cachedRef)
            || (!isNull _currentRef && abs(getDir _currentRef - _prevRefDir) > 1.0);

        if (_refChanged) then {
            _state set ["cachedRefObj", _currentRef];
            _state set ["cachedRefDir", if (!isNull _currentRef) then { getDir _currentRef } else { 0 }];
            if (!isNull _currentRef) then {
                [_prefix, _state, _snapGround] call SP_fnc_fill;
            };
        };

        // ── Detect distance object ──────────────────────────────────────────────
        private _distObj = objNull;
        if (!isNull _currentRef) then {
            private _synced = (get3DENConnections _currentRef) select { _x isEqualType [] };
            _synced = (_synced select { (_x select 0) == "Sync" && (_x select 1) isEqualType objNull }) apply { _x select 1 };
            { if (!(typeOf _x in SP_waypointClasses) && !isNull _x && typeOf _x != "" && typeOf _x != "EMPTY") exitWith { _distObj = _x; }; } forEach _synced;
        };

        // ── Dirty check ────────────────────────────────────────────────────────
        private _controlPoints = _waypoints apply { (getPosASL _x) vectorAdd [0,0,-5] };
        private _cachedPositions = _state getOrDefault ["cachedPositions", []];

        private _dirty = (count _controlPoints != count _cachedPositions)
            || {
                private _changed = false;
                for "_i" from 0 to (count _controlPoints - 1) do {
                    private _a = _controlPoints select _i;
                    private _b = _cachedPositions select _i;
                    if (abs((_a select 0) - (_b select 0)) > 0.01
                     || abs((_a select 1) - (_b select 1)) > 0.01
                     || abs((_a select 2) - (_b select 2)) > 0.01) then {
                        _changed = true;
                    };
                };
                _changed
            };

        private _cachedDistPos = _state getOrDefault ["cachedDistObjPos", [0,0,0]];
        private _distPos = if (!isNull _distObj) then { getPosASL _distObj } else { [0,0,0] };
        if (_distPos distance _cachedDistPos > 0.05) then { _dirty = true; };

        if (_dirty) then {
            _state set ["cachedPositions", _controlPoints];
            _state set ["cachedDistObjPos", _distPos];

            private _spacing = if (!isNull _distObj) then {
                (_currentRef distance _distObj) max 0.1
            } else {
                (SP_settings get "spacing") max 0.1
            };
            private _resolution = SP_settings get "resolution";
            private _previewSamples   = [_controlPoints, 0.5, _resolution] call SP_fnc_sampleSpline;
            private _placementSamples = [_controlPoints, _spacing, _resolution] call SP_fnc_sampleSpline;
            _state set ["cachedPreviewSamples",   _previewSamples];
            _state set ["cachedPlacementSamples", _placementSamples];

            private _generatedObjects = _state getOrDefault ["generatedObjects", []];

            // Live update: move existing objects in-place if count matches
            if (count _placementSamples == count _generatedObjects && _generatedObjects isNotEqualTo []) then {
                private _alignToDir = SP_settings get "alignToDir";
                private _refDir = if (!isNull _currentRef) then { getDir _currentRef } else { 0 };
                {
                    private _sample  = _placementSamples select _forEachIndex;
                    private _posASL  = _sample select 0;
                    private _tangent = _sample select 1;
                    private _posATL  = ASLToATL _posASL;
                    if (_snapGround) then { _posATL set [2, 0]; };
                    _x set3DENAttribute ["position", _posATL];
                    if (_alignToDir) then {
                        private _h = (_tangent select 0) atan2 (_tangent select 1);
                        if (_h < 0) then { _h = _h + 360; };
                        private _pitch = 0;
                        private _bank  = 0;
                        if (!_snapGround) then {
                            private _hDist = sqrt((_tangent select 0)^2 + (_tangent select 1)^2) max 0.0001;
                            private _elevation = (_tangent select 2) atan2 _hDist;
                            _pitch = -(_elevation * (_tangent select 1) / _hDist);
                            _bank  = _elevation * (_tangent select 0) / _hDist;
                        };
                        _x set3DENAttribute ["rotation", [_pitch, _bank, (_h + _refDir + 90) % 360]];
                    };
                } forEach _generatedObjects;
            } else {
                // Count changed or no objects yet
                if (!isNull _currentRef || _generatedObjects isNotEqualTo []) then {
                    [_prefix, _state, _snapGround] call SP_fnc_fill;
                };
            };
        };

        // ── Draw waypoint spheres ─────────────────────────────────────────────
        {
            drawIcon3D [
                "\a3\ui_f\data\map\markers\nato\b_unknown.paa",
                _color,
                ASLToAGL (getPosASL _x),
                0.5, 0.5, 0,
                (_x get3DENAttribute "name") select 0,
                1, 0.03
            ];
        } forEach _waypoints;

        // ── Draw spline preview ───────────────────────────────────────────────
        private _previewSamples = _state getOrDefault ["cachedPreviewSamples", []];
        if (count _previewSamples >= 2) then {
            private _prevPos = (_previewSamples select 0) select 0;
            {
                private _pos = _x select 0;
                drawLine3D [
                    ASLToAGL _prevPos,
                    ASLToAGL _pos,
                    _color
                ];
                _prevPos = _pos;
            } forEach (_previewSamples select [1, count _previewSamples - 1]);
        };

        // ── Draw placement dots ───────────────────────────────────────────────
        {
            private _pos = _x select 0;
            drawIcon3D [
                "\a3\ui_f\data\map\markers\nato\n_unknown.paa",
                [1, 1, 1, 0.6],
                ASLToAGL _pos,
                0.2, 0.2, 0,
                "", 0, 0
            ];
        } forEach (_state getOrDefault ["cachedPlacementSamples", []]);

    }; // count _waypoints >= 2

} forEach _groups;
