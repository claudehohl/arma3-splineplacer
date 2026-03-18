class CfgPatches {
    class SplinePlacer {
        name        = "SplinePlacer - Eden Spline Placer";
        author      = "SplinePlacer";
        authorUrl   = "";
        units[]     = { "SP_Waypoint", "SP_WaypointGround" };
        weapons[]   = {};
        requiredVersion = 2.18;
        requiredAddons[] = {};
        version     = "1.0";
        versionStr  = "1.0.0";
    };
};

class CfgFunctions {
    class SP {
        class SplinePlacer {
            file = "\z\splineplacer\addons\main\functions";
            class init                  {};
            class sampleSpline          {};
            class draw                  {};
            class fill                  {};
            class getWaypoints          {};
        };
    };
};

class CfgVehicles {
    class Logic;
    class SP_Waypoint : Logic {
        scope             = 2;
        scopeEditor       = 2;
        displayName       = "SP Waypoint";
        editorCategory    = "SP_Cat";
        editorSubcategory = "SP_SubCat_Waypoints";
        Icon              = "\a3\ui_f\data\map\markers\nato\n_unknown.paa";
        editorPreview     = "";
        class AttributeValues {
            name = "wp_01";
        };
    };
    class SP_WaypointGround : SP_Waypoint {
        displayName       = "SP Waypoint (Ground)";
        Icon        = "\a3\ui_f\data\map\markers\nato\n_installation.paa";
    };
};

class CfgEditorCategories {
    class SP_Cat {
        displayName = "SplinePlacer";
    };
};

class CfgEditorSubcategories {
    class SP_SubCat_Waypoints {
        displayName = "Waypoints";
    };
};

class RscTitles {};

class Cfg3DEN {
    class Attributes {};
    class EventHandlers {
        class SplinePlacer {
            onTerrainNew        = "call SP_fnc_init;";
            onMissionNew        = "call SP_fnc_init;";
            onMissionLoad       = "call SP_fnc_init;";
            onMissionPreviewEnd = "[] spawn { sleep 0.5; call SP_fnc_init; };";
        };
    };
};
