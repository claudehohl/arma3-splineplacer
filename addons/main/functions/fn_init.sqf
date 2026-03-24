/*
    SP_fnc_init
    Called via Cfg3DEN >> EventHandlers >> SplinePlacer >> onTerrainNew.
    Fires every time the Eden Editor opens or loads a new terrain.
    Eden is already fully open at this point.
*/

// ─── Global state ─────────────────────────────────────────────────────────────
SP_settings = createHashMap;
SP_settings set ["classname",  "Land_Pipe_fence_4m_F"];
SP_settings set ["spacing",    4.0];
SP_settings set ["alignToDir", true];
SP_settings set ["snapGround", true];
SP_settings set ["resolution", 20];

SP_waypointClasses    = ["SP_Waypoint", "SP_WaypointGround"];
SP_splines            = createHashMap;   // key = prefix (e.g. "s1") → per-spline state HashMap
SP_activePrefix       = "s1";            // prefix for newly placed waypoints
SP_splineCounter      = 1;               // next ID number to assign
SP_needsRecovery      = true;            // fn_draw will scan for tagged objects on first frame
SP_handledEntities    = createHashMap;   // tracks already-processed entities to prevent double-fire
SP_dirty              = true;           // when true, fn_draw runs full recompute; when false, only draws
SP_dragEHs            = createHashMap;  // str obj → true (objects with Dragged3DEN registered)
SP_colorPalette       = [
    [0.2, 1.0, 0.2, 1.0],
    [0.2, 0.8, 1.0, 1.0],
    [1.0, 0.6, 0.2, 1.0],
    [1.0, 0.2, 0.8, 1.0],
    [1.0, 1.0, 0.2, 1.0]
];

// ─── Recover spline counter from existing waypoints (mission reload) ──────────
{
    private _name = (_x get3DENAttribute "name") select 0;
    if (_name regexMatch "^s\d+_\d+$") then {
        private _num = parseNumber (_name regexReplace ["^s", ""] regexReplace ["_\d+$", ""]);
        if (_num > SP_splineCounter) then { SP_splineCounter = _num; };
    };
} forEach (allMissionObjects "SP_Waypoint");
SP_activePrefix = format ["s%1", SP_splineCounter];

// ─── Draw3D event handler ─────────────────────────────────────────────────────
if (!isNil "SP_drawEH") then {
    removeMissionEventHandler ["Draw3D", SP_drawEH];
};
SP_drawEH = addMissionEventHandler ["Draw3D", { call SP_fnc_draw; }];

// ─── Eden overlay (active spline indicator + New Spline button) ───────────────
// Re-create controls every init (terrain reload removes previous display children)
private _display = findDisplay 313;
if (!isNull _display) then {

    // Remove old controls and HUD key handler if they exist
    {
        private _ctrl = uiNamespace getVariable [_x, controlNull];
        if (!isNull _ctrl) then { ctrlDelete _ctrl; };
    } forEach ["SP_overlayBg", "SP_overlayLabel", "SP_overlayBtn", "SP_overlayLbl"];
    if (!isNil "SP_hudKeyEH") then {
        _display displayRemoveEventHandler ["KeyDown", SP_hudKeyEH];
    };

    // SafeZone-Anker: rechte Kante + obere Kante
    private _rX = safeZoneX + safeZoneW;
    private _tY = safeZoneY;

    // Background panel
    private _bg = _display ctrlCreate ["RscBackground", -1];
    _bg ctrlSetPosition [_rX - 0.653, _tY + 0.134, 0.233, 0.05];
    _bg ctrlSetBackgroundColor [0, 0, 0, 0.4];
    _bg ctrlCommit 0;
    uiNamespace setVariable ["SP_overlayBg", _bg];

    // Label: "Spline: sN"
    private _initColor = SP_colorPalette select ((SP_splineCounter - 1) mod count SP_colorPalette);
    private _label = _display ctrlCreate ["RscText", -1];
    _label ctrlSetPosition [_rX - 0.65, _tY + 0.076, 0.27, 0.1];
    _label ctrlSetText format ["Spline: %1", SP_activePrefix];
    _label ctrlSetTextColor _initColor;
    _label ctrlSetFont "EtelkaNarrowMediumPro";
    _label ctrlSetFontHeight 0.05;
    _label ctrlCommit 0;
    uiNamespace setVariable ["SP_overlayLabel", _label];

    // Button: [+]
    private _btn = _display ctrlCreate ["RscButton", -1];
    _btn ctrlSetPosition [_rX - 0.47, _tY + 0.136, 0.05, 0.048];
    _btn ctrlSetFont "EtelkaNarrowMediumPro";
    _btn ctrlSetFontHeight 0.060;
    _btn ctrlCommit 0;
    uiNamespace setVariable ["SP_overlayBtn", _btn];

    // Label über dem Button
    private _lbl = _display ctrlCreate ["RscText", -1];
    _lbl ctrlSetPosition [_rX - 0.458, _tY + 0.023, 0.10, 0.2];
    _lbl ctrlSetText "+";
    _lbl ctrlSetFont "EtelkaNarrowMediumPro";
    _lbl ctrlSetFontHeight 0.060;
    _lbl ctrlSetTextColor [1, 1, 1, 1];
    _lbl ctrlCommit 0;
    uiNamespace setVariable ["SP_overlayLbl", _lbl];

    // Button action: generate new spline ID, update label + color
    _btn ctrlAddEventHandler ["ButtonClick", {
        SP_splineCounter = SP_splineCounter + 1;
        SP_activePrefix  = format ["s%1", SP_splineCounter];

        private _color = SP_colorPalette select ((SP_splineCounter - 1) mod count SP_colorPalette);

        private _lbl = uiNamespace getVariable ["SP_overlayLabel", controlNull];
        if (!isNull _lbl) then {
            _lbl ctrlSetText format ["Spline: %1", SP_activePrefix];
            _lbl ctrlSetTextColor _color;
        };
    }];

    // Hide/show overlay when Backspace toggles the Eden HUD
    // Guard: only react when no text field has focus (same condition Eden uses internally)
    SP_hudKeyEH = _display displayAddEventHandler ["KeyDown", {
        params ["_display", "_key"];
        if (_key != 14) exitWith { false };
        if (ctrlType (focusedCtrl _display) == 2) exitWith { false };
        private _bg = uiNamespace getVariable ["SP_overlayBg", controlNull];
        if (isNull _bg) exitWith { false };
        private _show = !(ctrlShown _bg);
        {
            private _ctrl = uiNamespace getVariable [_x, controlNull];
            if (!isNull _ctrl) then { _ctrl ctrlShow _show; };
        } forEach ["SP_overlayBg", "SP_overlayLabel", "SP_overlayBtn", "SP_overlayLbl"];
        false
    }];
};

// ─── Auto-increment waypoint names ───────────────────────────────────────────
if (!isNil "SP_entityAddedEH") then {
    remove3DENEventHandler ["OnEditableEntityAdded", SP_entityAddedEH];
};
SP_entityAddedEH = add3DENEventHandler ["OnEditableEntityAdded", {
    params ["_entity"];
    if !(_entity isEqualType objNull) exitWith {};
    if !(typeOf _entity in SP_waypointClasses) exitWith {};

    SP_dirty = true;

    // Guard against double-fire: set3DENAttribute can re-trigger OnEditableEntityAdded.
    private _key = str _entity;
    if (_key in keys SP_handledEntities) exitWith {};
    SP_handledEntities set [_key, true];

    // Defer one frame: Eden applies the copied name AFTER the EH fires for duplicates.
    // Reading the name after sleep 0 gives us the correct source name for Ctrl+V copies.
    [_entity] spawn {
        params ["_entity"];
        // Wait one frame so Eden can apply the copied name (for Ctrl+V duplicates).
        sleep 0;

        // Guard: fn_init may not have run yet if mission was loaded while old EH was still active
        if (isNil "SP_waypointClasses") exitWith {};

        // For duplicates: name is now the source name (e.g. "s1_03").
        // For fresh placements: it's the config default (e.g. "wp_01").
        private _currentName = (_entity get3DENAttribute "name") select 0;

        private _prefix = if (_currentName regexMatch "^s\d+_\d+$") then {
            _currentName regexReplace ["_\d+$", ""]
        } else {
            SP_activePrefix
        };

        private _allWps = allMissionObjects "SP_Waypoint";
        if !(_entity in _allWps) exitWith {};

        // Already has a valid unique name (loaded from saved mission) → don't rename.
        // Must use "if condition exitWith" form directly in spawn scope (not nested in then-block),
        // otherwise exitWith would only exit the then-block, not the spawn script.
        if (_currentName regexMatch "^s\d+_\d+$" && {
            0 == count (_allWps select {
                _x != _entity && ((_x get3DENAttribute "name") select 0) == _currentName
            })
        }) exitWith {};

        // Find highest NN already used in this prefix group.
        // Exclude _entity itself: Eden may have already assigned it a name (e.g. paste conflict
        // resolution), which would inflate the count and cause an off-by-one.
        private _existing = _allWps select { _x != _entity };
        private _maxNum = 0;
        {
            private _n = (_x get3DENAttribute "name") select 0;
            if (_n regexMatch (format ["^%1_\d+$", _prefix])) then {
                private _num = parseNumber (_n regexReplace [format ["^%1_", _prefix], ""]);
                if (_num > _maxNum) then { _maxNum = _num; };
            };
        } forEach _existing;

        private _nextNum = _maxNum + 1;
        private _pad     = if (_nextNum < 10) then [{ "0" }, { "" }];
        private _newName = format ["%1_%2%3", _prefix, _pad, _nextNum];

        _entity set3DENAttribute ["name", _newName];

        // Lift waypoint 5 m above ground so it doesn't overlap placed objects
        private _pos = getPosATL _entity;
        _entity set3DENAttribute ["position", [_pos select 0, _pos select 1, (_pos select 2) + 5]];

        // Re-dirty after rename so draw phase picks up the final name
        SP_dirty = true;
    };
}];

// ─── Mark dirty when any entity is removed ───────────────────────────────────
if (!isNil "SP_entityRemovedEH") then {
    remove3DENEventHandler ["OnEditableEntityRemoved", SP_entityRemovedEH];
};
SP_entityRemovedEH = add3DENEventHandler ["OnEditableEntityRemoved", {
    SP_dirty = true;
}];
