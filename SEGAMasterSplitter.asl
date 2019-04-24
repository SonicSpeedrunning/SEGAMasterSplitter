/*
    SEGA Master Splitter

    Splitter designed to handle multiple 8 and 16 bit SEGA games running on various emulators
*/

state("retroarch") {}
state("Fusion") {}
state("gens") {}
state("SEGAGameRoom") {}
state("SEGAGenesisClassics") {}
// state("emuhawk") {} // uncommment to enable experimental BizHawk SMS support

init
{
    vars.gamename = timer.Run.GameName;
    vars.livesplitGameName = vars.gamename;
    vars.isBizHawk = false;
    long memoryOffset = 0;
    long smsMemoryOffset = 0;
    IntPtr baseAddress;
    IntPtr injectionMem = (IntPtr) 0;

    long genOffset = 0;
    long smsOffset = 0;
    baseAddress = modules.First().BaseAddress;
    bool isBigEndian = false;
    bool isFusion = false;
    
    switch ( game.ProcessName.ToLower() ) {
        case "retroarch":
            ProcessModuleWow64Safe gpgx = modules.Where(m => m.ModuleName == "genesis_plus_gx_libretro.dll").First();
            baseAddress = gpgx.BaseAddress;
            if ( game.Is64Bit() ) {
                SigScanTarget target = new SigScanTarget(0, "85 C9 74 11 83 F9 02 B8 00 00 00 00 48 0F 44 05 ?? ?? ?? ?? C3 48 8B 05 ?? ?? ?? ?? 80 78 01 00 74 0E 48 8B 40 10 C3");
                IntPtr codeOffset = vars.LookUpInDLL( game, gpgx, target );
                long memoryReference = memory.ReadValue<int>( codeOffset + 0x10 );
                long refLocation = ( (long ) codeOffset + 0x14 + memoryReference );
                memoryOffset = memory.ReadValue<int>( (IntPtr) refLocation );
            } else {
                SigScanTarget target = new SigScanTarget(0, "8B 44 24 04 85 C0 74 18 83 F8 02 BA 00 00 00 00 B8 ?? ?? ?? ?? 0F 45 C2 C3 8D B4 26 00 00 00 00");
                IntPtr codeOffset = vars.LookUpInDLL( game, gpgx, target );
                long memoryReference = memory.ReadValue<int>( codeOffset + 0x11 );
                memoryOffset = memoryReference;
            }
            break;
        case "gens":
            genOffset = 0x40F5C;
            break;
        case "fusion":
            
            genOffset = 0x2A52D4;
            smsOffset = 0x2A52D8;
            isBigEndian = true;
            isFusion = true;
            break;
        case "segagameroom":
            baseAddress = modules.Where(m => m.ModuleName == "GenesisEmuWrapper.dll").First().BaseAddress;
            genOffset = 0xB677E8;
            break;
        case "segagenesisclassics":
            genOffset = 0x71704;
            break;
        case "emuhawk":
            // game == Bizhawk process
            vars.isBizHawk = true;
            memoryOffset = vars.BizHawksetup( game, memory );
            break;

    }
    if ( genOffset > 0 ) {
        memoryOffset = memory.ReadValue<int>(IntPtr.Add(baseAddress, (int)genOffset) );
    }
    smsMemoryOffset = memoryOffset;

    if ( isFusion ) {
        smsMemoryOffset = memory.ReadValue<int>(IntPtr.Add(baseAddress, (int)smsOffset) ) + (int) 0xC000;
    }

    if ( memoryOffset == 0 && ( !isFusion || smsMemoryOffset == 0xC000 ) ) {
        throw new NullReferenceException (String.Format("Memory offset not yet found. Base Address: 0x{0:X}", (long) baseAddress ));
        Thread.Sleep(500);
    }

    vars.DebugOutput(String.Format("memory should start at {0:X}", memoryOffset));
    vars.DebugOutput(String.Format("SMS memory should start at {0:X}", smsMemoryOffset));
    vars.isBigEndian = isBigEndian;
    Action reInitialise = () => {
        vars.isIGT = false;
        vars.loading = false;
        vars.igttotal = 0;

        vars.ingame = false;

        vars.levelselectoffset = 0;
        vars.isGenSonic1 = false;
        vars.isGenSonic1or2 = false;
        vars.isS3K = false;
        vars.isSK = false;
        vars.isSMSGGSonic2 = false;
        vars.isSonicChaos = false;
        vars.isSonicCD = false;
        vars.nextsplit = "";
        vars.startTrigger = 0x8C;
        vars.splitInXFrames = -1;
        vars.bossdown = false;
        vars.levelselectbytes = new byte[] {0x01}; // Default as most are 0 - off, 1 - on
        IDictionary<string, string> expectednextlevel = new Dictionary<string, string>();
        vars.nextzonemap = false;
        vars.stopwatch = new Stopwatch();
        vars.livesplitGameName = vars.gamename;
        switch ( (string) vars.gamename ) {
            /**********************************************************************************
                ANCHOR START Alex Kidd in Miracle World watchlist
            **********************************************************************************/
            case "Alex Kidd in Miracle World":
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x0023     ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x03C1     ) { Name = "trigger" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x0025     ) { Name = "lives" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1800     ) { Name = "complete" },
                };
                break;
            /**********************************************************************************
                ANCHOR START Sonic 3D Blast Memory watchlist
            **********************************************************************************/
            case "Sonic 3D Blast":
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0x067F : 0x067E ) ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +  0xF749                           ) { Name = "ingame" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xD189 : 0xD188 ) ) { Name = "ppboss" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0x0BA9 : 0x0BA8 ) ) { Name = "ffboss" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0x06A3 : 0x06A2 ) ) { Name = "emeralds" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0x0A1B : 0x0A1A ) ) { Name = "fadeout" },
                    new MemoryWatcher<ushort>(  (IntPtr)memoryOffset + 0x0A5C                          ) { Name = "levelframecount" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + 0x040D                          ) { Name = "levelselect" },
                };
                vars.levelselectoffset = (IntPtr)memoryOffset + 0x040D;
                vars.igttotal = 0;
                vars.isIGT = true;
                
                break;

            /**********************************************************************************
                ANCHOR START Sonic Spinball (Genesis / Mega Drive) 
            **********************************************************************************/
            case "Sonic Spinball (Genesis / Mega Drive)":
                vars.levelselectoffset = (IntPtr)memoryOffset + ( isBigEndian ? 0xF8F8 : 0xF8F9 );
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0x067F : 0x067E ) ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xF2FC : 0xF2FD ) ) { Name = "trigger" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFF69 : 0xFF68 ) ) { Name = "menuoption" },
                    new MemoryWatcher<ushort>(  (IntPtr)memoryOffset + 0xFF6C                            ) { Name = "menutimeout" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0x3CB7 : 0x3CB6 ) ) { Name = "gamemode" },

                    new MemoryWatcher<byte>(  vars.levelselectoffset                         ) { Name = "levelselect" },
                };

                vars.lastmenuoption = 999;
                vars.skipsplit = false;
                break;
            /**********************************************************************************
                ANCHOR START Sonic the HedgeHog 1 & 2 Genesis watchlist
            **********************************************************************************/
            case "Sonic the Hedgehog (Genesis / Mega Drive)":
            case "Sonic the Hedgehog":
            case "Sonic 1": 
            case "Sonic 1 (Genesis)":
            case "Sonic 1 (Mega Drive)":
                vars.gamename = "Sonic the Hedgehog (Genesis / Mega Drive)";
            
                const string GREEN_HILL_1 = "0-0";
                const string GREEN_HILL_2 = "0-1";
                const string GREEN_HILL_3 = "0-2";
                const string MARBLE_1 = "2-0";
                const string MARBLE_2 = "2-1";
                const string MARBLE_3 = "2-2";
                const string SPRING_YARD_1 = "4-0";
                const string SPRING_YARD_2 = "4-1";
                const string SPRING_YARD_3 = "4-2";
                const string LABYRINTH_1 = "1-0";
                const string LABYRINTH_2 = "1-1";
                const string LABYRINTH_3 = "1-2";
                const string STAR_LIGHT_1 = "3-0";
                const string STAR_LIGHT_2 = "3-1";
                const string STAR_LIGHT_3 = "3-2";
                const string SCRAP_BRAIN_1 = "5-0";
                const string SCRAP_BRAIN_2 = "5-1";
                const string SCRAP_BRAIN_3 = "1-3"; // LUL
                const string FINAL_ZONE = "5-2"; 
                const string AFTER_FINAL_ZONE = "99-0";
                
                expectednextlevel.Clear();
                expectednextlevel[GREEN_HILL_1] = GREEN_HILL_2;
                expectednextlevel[GREEN_HILL_2] = GREEN_HILL_3;
                expectednextlevel[GREEN_HILL_3] = MARBLE_1;
                expectednextlevel[MARBLE_1] = MARBLE_2;
                expectednextlevel[MARBLE_2] = MARBLE_3;
                expectednextlevel[MARBLE_3] = SPRING_YARD_1;
                expectednextlevel[SPRING_YARD_1] = SPRING_YARD_2;
                expectednextlevel[SPRING_YARD_2] = SPRING_YARD_3;
                expectednextlevel[SPRING_YARD_3] = LABYRINTH_1;
                expectednextlevel[LABYRINTH_1] = LABYRINTH_2;
                expectednextlevel[LABYRINTH_2] = LABYRINTH_3;
                expectednextlevel[LABYRINTH_3] = STAR_LIGHT_1;
                expectednextlevel[STAR_LIGHT_1] = STAR_LIGHT_2;
                expectednextlevel[STAR_LIGHT_2] = STAR_LIGHT_3;
                expectednextlevel[STAR_LIGHT_3] = SCRAP_BRAIN_1;
                expectednextlevel[SCRAP_BRAIN_1] = SCRAP_BRAIN_2;
                expectednextlevel[SCRAP_BRAIN_2] = SCRAP_BRAIN_3;
                expectednextlevel[SCRAP_BRAIN_3] = FINAL_ZONE;
                expectednextlevel[FINAL_ZONE] = AFTER_FINAL_ZONE; 
                
                vars.levelselectoffset = (IntPtr) memoryOffset + ( isBigEndian ? 0xFFE0 : 0xFFE1 );
                vars.isGenSonic1 = true;
                goto case "Sonic the Hedgehog 2 (Genesis / Mega Drive)";
            case "Sonic the Hedgehog 2 (Genesis / Mega Drive)":
            case "Sonic the Hedgehog 2":
            case "Sonic 2":
            case "Sonic 2 (Genesis)":
            case "Sonic 2 (Mega Drive)":
                if ( !vars.isGenSonic1 ) {
                    vars.levelselectoffset = (IntPtr) memoryOffset + ( isBigEndian ? 0xFFD0 : 0xFFD1 );

                    vars.gamename = "Sonic the Hedgehog 2 (Genesis / Mega Drive)";
                    const string EMERALD_HILL_1 = "0-0";
                    const string EMERALD_HILL_2 = "0-1";
                    const string CHEMICAL_PLANT_1 = "13-0";
                    const string CHEMICAL_PLANT_2 = "13-1";
                    const string AQUATIC_RUIN_1 = "15-0";
                    const string AQUATIC_RUIN_2 = "15-1";
                    const string CASINO_NIGHT_1 = "12-0";
                    const string CASINO_NIGHT_2 = "12-1";
                    const string HILL_TOP_1 = "7-0";
                    const string HILL_TOP_2 = "7-1";
                    const string MYSTIC_CAVE_1 = "11-0";
                    const string MYSTIC_CAVE_2 = "11-1";
                    const string OIL_OCEAN_1 = "10-0";
                    const string OIL_OCEAN_2 = "10-1";
                    const string METROPOLIS_1 = "4-0";
                    const string METROPOLIS_2 = "4-1";
                    const string METROPOLIS_3 = "5-0";
                    const string SKY_CHASE = "16-0";
                    const string WING_FORTRESS = "6-0";
                    const string DEATH_EGG = "14-0";
                    const string AFTER_DEATH_EGG = "99-0";
                    expectednextlevel.Clear();
                    expectednextlevel[EMERALD_HILL_1] = EMERALD_HILL_2;
                    expectednextlevel[EMERALD_HILL_2] = CHEMICAL_PLANT_1;
                    expectednextlevel[CHEMICAL_PLANT_1] = CHEMICAL_PLANT_2;
                    expectednextlevel[CHEMICAL_PLANT_2] = AQUATIC_RUIN_1;
                    expectednextlevel[AQUATIC_RUIN_1] = AQUATIC_RUIN_2;
                    expectednextlevel[AQUATIC_RUIN_2] = CASINO_NIGHT_1;
                    expectednextlevel[CASINO_NIGHT_1] = CASINO_NIGHT_2;
                    expectednextlevel[CASINO_NIGHT_2] = HILL_TOP_1;
                    expectednextlevel[HILL_TOP_1] = HILL_TOP_2;
                    expectednextlevel[HILL_TOP_2] = MYSTIC_CAVE_1;
                    expectednextlevel[MYSTIC_CAVE_1] = MYSTIC_CAVE_2;
                    expectednextlevel[MYSTIC_CAVE_2] = OIL_OCEAN_1;
                    expectednextlevel[OIL_OCEAN_1] = OIL_OCEAN_2;
                    expectednextlevel[OIL_OCEAN_2] = METROPOLIS_1;
                    expectednextlevel[METROPOLIS_1] = METROPOLIS_2;
                    expectednextlevel[METROPOLIS_2] = METROPOLIS_3;
                    expectednextlevel[METROPOLIS_3] = SKY_CHASE;
                    expectednextlevel[SKY_CHASE] = WING_FORTRESS;
                    expectednextlevel[WING_FORTRESS] = DEATH_EGG;
                    expectednextlevel[DEATH_EGG] = AFTER_DEATH_EGG;
                }
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xFE24 : 0xFE25 )    ) { Name = "seconds" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xFE23 : 0xFE22 )    ) { Name = "minutes" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xFE12 : 0xFE13 )    ) { Name = "lives" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xFE18 : 0xFE19 )    ) { Name = "continues" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xFE10 : 0xFE11 )    ) { Name = "zone" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xFE11 : 0xFE10 )    ) { Name = "act" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xF600 : 0xF601 )    ) { Name = "trigger" },
                    new MemoryWatcher<ushort>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFE04 : 0xFE04 )    ) { Name = "levelframecount" },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xF7D2 ) { Name = "timebonus" },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xFE28 ) { Name = "scoretally" },
                    new MemoryWatcher<byte>(  vars.levelselectoffset     ) { Name = "levelselect" },

                };
                vars.isGenSonic1or2 = true;
                vars.isIGT = true;


                vars.expectednextlevel = expectednextlevel;
                break;
            /**********************************************************************************
                ANCHOR START Sonic the Hedgehog 3 & Knuckles watchlist
            **********************************************************************************/
            case "Sonic & Knuckles":
            case "Sonic and Knuckles":
                vars.isSK = true;
                goto case "Sonic 3 & Knuckles";
            case "Sonic 3 & Knuckles":
            case "Sonic 3 and Knuckles":
            case "Sonic 3 Complete":
                vars.gamename = "Sonic 3 & Knuckles";
                vars.levelselectoffset = (IntPtr) memoryOffset + ( isBigEndian ? 0xFFE0 : 0xFFE1 );
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xEE4E ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEE4E : 0xEE4F ) ) { Name = "zone" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEE4F : 0xEE4E ) ) { Name = "act" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + 0xFFFC ) { Name = "reset" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xF600 : 0xF601 ) ) { Name = "trigger" },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xF7D2 ) { Name = "timebonus" },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xFE28 ) { Name = "scoretally" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFF09 : 0xFF08 ) ) { Name = "chara" },
                    new MemoryWatcher<ulong>( (IntPtr)memoryOffset + 0xFC00) { Name = "dez2end" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xB1E5 : 0xB1E4 ) ) { Name = "ddzboss" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xB279 : 0xB278 ) ) { Name = "sszboss" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEEE4 : 0xEEE5 ) ) { Name = "delactive" },

                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEF4B : 0xEF4A ) ) { Name = "savefile" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFDEB : 0xFDEA ) ) { Name = "savefilezone" },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + ( isBigEndian ? 0xF648 : 0xF647 ) ) { Name = "waterlevel" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFE25 : 0xFE24 ) ) { Name = "centiseconds" },
                    new MemoryWatcher<byte>(  vars.levelselectoffset     ) { Name = "levelselect" },
                };
                vars.nextzone = 0;
                vars.nextact = 1;
                vars.dez2split = false;
                vars.ddzsplit = false;
                vars.sszsplit = false; //boss is defeated twice
                vars.savefile = 255;
                vars.processingzone = false;
                vars.skipsAct1Split = false;
                vars.isS3K = true;
                break;
            /**********************************************************************************
                ANCHOR START Sonic the Hedgehog (Master System) watchlist
            **********************************************************************************/
            case "Sonic the Hedgehog (Master System)":
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x123E     ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1000     ) { Name = "state" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1203     ) { Name = "input" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x12D5     ) { Name = "endBoss" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x122C     ) { Name = "scorescreen" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1FEA     ) { Name = "scorescd" },
                    new MemoryWatcher<int >(  (IntPtr)smsMemoryOffset +  0x1212   ) { Name = "timebonus" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1C08   ) { Name = "menucheck1" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1C0A   ) { Name = "menucheck2" },
                };
                
                break;
            /**********************************************************************************
                ANCHOR START Sonic the Hedgehog (Game Gear / Master System) watchlist
            **********************************************************************************/
            case "Sonic the Hedgehog 2 (Game Gear / Master System)":
            case "Sonic 2 Rebirth":
                vars.gamename = "Sonic the Hedgehog 2 (Game Gear / Master System)";
                vars.levelselectbytes = new byte[] {0x0D};
                vars.levelselectoffset = (IntPtr) smsMemoryOffset + 0x112C;
                vars.emeraldcountoffset = (IntPtr) smsMemoryOffset + 0x12BD;
                vars.emeraldflagsoffset = (IntPtr) smsMemoryOffset + 0x12C5;
                vars.startTrigger = 68;
                vars.isSMSGGSonic2 = true;
                vars.watchers = new MemoryWatcherList
                {

                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x12B9     ) { Name = "seconds" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x12BA    ) { Name = "minutes" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1298     ) { Name = "lives" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1298 /* for simplicity */    ) { Name = "continues" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1295    ) { Name = "zone" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1296     ) { Name = "act" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1293     ) { Name = "trigger" },
                    new MemoryWatcher<ushort>(  (IntPtr)smsMemoryOffset + 0x12BA  /* for simplicity */  ) { Name = "levelframecount" },
                    new MemoryWatcher<byte>( (IntPtr)smsMemoryOffset + 0x12C8     ) { Name = "systemflag" },
                    new MemoryWatcher<byte>(  vars.levelselectoffset     ) { Name = "levelselect" },
                    new MemoryWatcher<byte>(  vars.emeraldcountoffset     ) { Name = "emeraldcount" },
                    new MemoryWatcher<byte>(  vars.emeraldflagsoffset     ) { Name = "emeraldflags" },
                    
                };
                vars.isIGT = true;
                const string UNDER_GROUND_1 = "0-0";
                const string UNDER_GROUND_2 = "0-1";
                const string UNDER_GROUND_3 = "0-2";
                const string SKY_HIGH_1 = "1-0";
                const string SKY_HIGH_2 = "1-1";
                const string SKY_HIGH_3 = "1-2";
                const string AQUA_LAKE_1 = "2-0";
                const string AQUA_LAKE_2 = "2-1";
                const string AQUA_LAKE_3 = "2-2";
                const string GREEN_HILLS_1 = "3-0";
                const string GREEN_HILLS_2 = "3-1";
                const string GREEN_HILLS_3 = "3-2";
                const string GIMMICK_MT_1 = "4-0";
                const string GIMMICK_MT_2 = "4-1";
                const string GIMMICK_MT_3 = "4-2";
                const string SCRAMBLED_EGG_1 = "5-0";
                const string SCRAMBLED_EGG_2 = "5-1";
                const string SCRAMBLED_EGG_3 = "5-2";
                const string CRYSTAL_EGG_1 = "6-0";
                const string CRYSTAL_EGG_2 = "6-1";
                const string CRYSTAL_EGG_3 = "6-2";
                const string S2SMS_GOOD_CREDITS = "7-1"; // Good Ending Credits
                const string S2SMS_END = "99-0"; // Good Ending Credits
                expectednextlevel.Clear();
                expectednextlevel[UNDER_GROUND_1] = UNDER_GROUND_2;
                expectednextlevel[UNDER_GROUND_2] = UNDER_GROUND_3;
                expectednextlevel[UNDER_GROUND_3] = SKY_HIGH_1;
                expectednextlevel[SKY_HIGH_1] = SKY_HIGH_2;
                expectednextlevel[SKY_HIGH_2] = SKY_HIGH_3;
                expectednextlevel[SKY_HIGH_3] = AQUA_LAKE_1;
                expectednextlevel[AQUA_LAKE_1] = AQUA_LAKE_2;
                expectednextlevel[AQUA_LAKE_2] = AQUA_LAKE_3;
                expectednextlevel[AQUA_LAKE_3] = GREEN_HILLS_1;
                expectednextlevel[GREEN_HILLS_1] = GREEN_HILLS_2;
                expectednextlevel[GREEN_HILLS_2] = GREEN_HILLS_3;
                expectednextlevel[GREEN_HILLS_3] = GIMMICK_MT_1;
                expectednextlevel[GIMMICK_MT_1] = GIMMICK_MT_2;
                expectednextlevel[GIMMICK_MT_2] = GIMMICK_MT_3;
                expectednextlevel[GIMMICK_MT_3] = SCRAMBLED_EGG_1;
                expectednextlevel[SCRAMBLED_EGG_1] = SCRAMBLED_EGG_2;
                expectednextlevel[SCRAMBLED_EGG_2] = SCRAMBLED_EGG_3;
                expectednextlevel[SCRAMBLED_EGG_3] = CRYSTAL_EGG_1;
                expectednextlevel[CRYSTAL_EGG_1] = CRYSTAL_EGG_2;
                expectednextlevel[CRYSTAL_EGG_2] = CRYSTAL_EGG_3;
                expectednextlevel[CRYSTAL_EGG_3] = S2SMS_GOOD_CREDITS;
                expectednextlevel[S2SMS_GOOD_CREDITS] = S2SMS_END;
                vars.expectednextlevel = expectednextlevel;
                break;
            /**********************************************************************************
                ANCHOR START Sonic Chaos watchlist
            **********************************************************************************/
            case "Sonic Chaos":

                byte chaosPlatform = memory.ReadValue<byte>((IntPtr) smsMemoryOffset + 0x111E );
                byte extraGGOffset = 0x0;
                switch( chaosPlatform ) {
                    case 0x06: 
                        extraGGOffset = 0x02;
                        break;
                    case 0x26:
                        // Master System
                        break;
                    default:
                        Thread.Sleep(500);
                        throw new NullReferenceException (String.Format("Can't Determine platform for Sonic Chaos {0}", chaosPlatform ));
                }

                vars.levelselectoffset = (IntPtr) smsMemoryOffset + 0x12CE + extraGGOffset;
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x12C9 + extraGGOffset    ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1297 + extraGGOffset    ) { Name = "zone" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1298 + extraGGOffset    ) { Name = "act" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1299 + extraGGOffset    ) { Name = "lives" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x12C3 + extraGGOffset    ) { Name = "continues" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x13E7     ) { Name = "endBoss" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x03C1     ) { Name = "trigger" },
                    new MemoryWatcher<byte>(  vars.levelselectoffset     ) { Name = "levelselect" },
                };

                const string TURQUOISE_HILL_1 = "0-0";
                const string TURQUOISE_HILL_2 = "0-1";
                const string TURQUOISE_HILL_3 = "0-2";
                const string GIGALOPOLIS_1 = "1-0";
                const string GIGALOPOLIS_2 = "1-1";
                const string GIGALOPOLIS_3 = "1-2";
                const string SLEEPING_EGG_1 = "2-0";
                const string SLEEPING_EGG_2 = "2-1";
                const string SLEEPING_EGG_3 = "2-2";
                const string MECHA_GREEN_HILL_1 = "3-0";
                const string MECHA_GREEN_HILL_2 = "3-1";
                const string MECHA_GREEN_HILL_3 = "3-2";
                const string AQUA_PLANET_1 = "4-0";
                const string AQUA_PLANET_2 = "4-1";
                const string AQUA_PLANET_3 = "4-2";
                const string ELECTRIC_EGG_1 = "5-0";
                const string ELECTRIC_EGG_2 = "5-1";
                const string ELECTRIC_EGG_3 = "5-2";
                const string AFTER_ELECTRIC_EGG_3 = "99-0";
                expectednextlevel.Clear();
                expectednextlevel[TURQUOISE_HILL_1] = TURQUOISE_HILL_2;
                expectednextlevel[TURQUOISE_HILL_2] = TURQUOISE_HILL_3;
                expectednextlevel[TURQUOISE_HILL_3] = GIGALOPOLIS_1;
                expectednextlevel[GIGALOPOLIS_1] = GIGALOPOLIS_2;
                expectednextlevel[GIGALOPOLIS_2] = GIGALOPOLIS_3;
                expectednextlevel[GIGALOPOLIS_3] = SLEEPING_EGG_1;
                expectednextlevel[SLEEPING_EGG_1] = SLEEPING_EGG_2;
                expectednextlevel[SLEEPING_EGG_2] = SLEEPING_EGG_3;
                expectednextlevel[SLEEPING_EGG_3] = MECHA_GREEN_HILL_1;
                expectednextlevel[MECHA_GREEN_HILL_1] = MECHA_GREEN_HILL_2;
                expectednextlevel[MECHA_GREEN_HILL_2] = MECHA_GREEN_HILL_3;
                expectednextlevel[MECHA_GREEN_HILL_3] = AQUA_PLANET_1;
                expectednextlevel[AQUA_PLANET_1] = AQUA_PLANET_2;
                expectednextlevel[AQUA_PLANET_2] = AQUA_PLANET_3;
                expectednextlevel[AQUA_PLANET_3] = ELECTRIC_EGG_1;
                expectednextlevel[ELECTRIC_EGG_1] = ELECTRIC_EGG_2;
                expectednextlevel[ELECTRIC_EGG_2] = ELECTRIC_EGG_3;
                expectednextlevel[ELECTRIC_EGG_3] = AFTER_ELECTRIC_EGG_3;

                vars.isSonicChaos = true;
                vars.expectednextlevel = expectednextlevel;
                break;
            /**********************************************************************************
                ANCHOR START Sonic CD '93 watchlist
            **********************************************************************************/
            case "Sonic CD":
                const string 
                    PALMTREE_PANIC_1    = "0-0", PALMTREE_PANIC_2    = "0-1", PALMTREE_PANIC_3    = "0-2",
                    COLLISION_CHAOS_1   = "1-0", COLLISION_CHAOS_2   = "1-1", COLLISION_CHAOS_3   = "1-2",
                    TIDAL_TEMPEST_1     = "2-0", TIDAL_TEMPEST_2     = "2-1", TIDAL_TEMPEST_3     = "2-2",
                    QUARTZ_QUADRANT_1   = "3-0", QUARTZ_QUADRANT_2   = "3-1", QUARTZ_QUADRANT_3   = "3-2", 
                    WACKY_WORKBENCH_1   = "4-0", WACKY_WORKBENCH_2   = "4-1", WACKY_WORKBENCH_3   = "4-2", 
                    STARDUST_SPEEDWAY_1 = "5-0", STARDUST_SPEEDWAY_2 = "5-1", STARDUST_SPEEDWAY_3 = "5-2", 
                    METALLIC_MADNESS_1  = "6-0", METALLIC_MADNESS_2  = "6-1", METALLIC_MADNESS_3  = "6-2", 
                    AFTER_METALLIC_MADNESS_3 = "99-0";
                
                var scdexpectednextlevel = new Dictionary<string, string>() {
                    { PALMTREE_PANIC_1,     /* -> */ PALMTREE_PANIC_2    },
                    { PALMTREE_PANIC_2,     /* -> */ PALMTREE_PANIC_3    },
                    { PALMTREE_PANIC_3,     /* -> */ COLLISION_CHAOS_1   },
                    { COLLISION_CHAOS_1,    /* -> */ COLLISION_CHAOS_2   },
                    { COLLISION_CHAOS_2,    /* -> */ COLLISION_CHAOS_3   },
                    { COLLISION_CHAOS_3,    /* -> */ TIDAL_TEMPEST_1     },
                    { TIDAL_TEMPEST_1,      /* -> */ TIDAL_TEMPEST_2     },
                    { TIDAL_TEMPEST_2,      /* -> */ TIDAL_TEMPEST_3     },
                    { TIDAL_TEMPEST_3,      /* -> */ QUARTZ_QUADRANT_1   },
                    { QUARTZ_QUADRANT_1,    /* -> */ QUARTZ_QUADRANT_2   },
                    { QUARTZ_QUADRANT_2,    /* -> */ QUARTZ_QUADRANT_3   },
                    { QUARTZ_QUADRANT_3,    /* -> */ WACKY_WORKBENCH_1   },
                    { WACKY_WORKBENCH_1,    /* -> */ WACKY_WORKBENCH_2   },
                    { WACKY_WORKBENCH_2,    /* -> */ WACKY_WORKBENCH_3   },
                    { WACKY_WORKBENCH_3,    /* -> */ STARDUST_SPEEDWAY_1 },
                    { STARDUST_SPEEDWAY_1,  /* -> */ STARDUST_SPEEDWAY_2 },
                    { STARDUST_SPEEDWAY_2,  /* -> */ STARDUST_SPEEDWAY_3 },
                    { STARDUST_SPEEDWAY_3,  /* -> */ METALLIC_MADNESS_1  },
                    { METALLIC_MADNESS_1,   /* -> */ METALLIC_MADNESS_2  },
                    { METALLIC_MADNESS_2,   /* -> */ METALLIC_MADNESS_3  },
                    { METALLIC_MADNESS_3,   /* -> */ AFTER_METALLIC_MADNESS_3 }
                };

    
                vars.expectednextlevel = scdexpectednextlevel;
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1516 : 0x1517 )    ) { Name = "seconds" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1515 : 0x1514 )    ) { Name = "minutes" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1508 : 0x1509 )    ) { Name = "lives" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1508 : 0x1509 )    ) { Name = "continues" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1506 : 0x1507 )    ) { Name = "zone" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1507 : 0x1506 )    ) { Name = "act" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xFA0E : 0xFA0F )    ) { Name = "trigger" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x152E : 0x152F )    ) { Name = "timeperiod" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1517 : 0x1516 )    ) { Name = "framesinsecond" },
                    
                    
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1571 : 0x1570 )    ) { Name = "timewarpminutes" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1572 : 0x1573 )    ) { Name = "timewarpseconds" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0x1573 : 0x1572 )    ) { Name = "timewarpframesinsecond" },

                    new MemoryWatcher<ushort>(  (IntPtr)memoryOffset + ( isBigEndian ? 0x1504 : 0x1504 )    ) { Name = "levelframecount" },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xF7D2 ) { Name = "timebonus" },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0x151A ) { Name = "scoretally" },
                    new MemoryWatcher<ulong>( (IntPtr)memoryOffset + 0xFB00 ) { Name = "fadeout" },
                    //new MemoryWatcher<byte>(  vars.levelselectoffset     ) { Name = "levelselect" },

                };
                vars.isIGT = true;
                vars.isSonicCD = true;
                vars.startTrigger = 1;
                vars.ms = 0;
                vars.waitforminutes = 0;
                vars.waitforseconds = 0;
                vars.waitforframes = 0;
                vars.wait = false;
                break;
            default:
                throw new NullReferenceException (String.Format("Game {0} not supported.", vars.gamename ));
        
            
        }
        vars.DebugOutput("Game from LiveSplit found: " + vars.gamename);
    };
    vars.reInitialise = reInitialise;
    vars.reInitialise();
}

update
{
    if ( vars.livesplitGameName != timer.Run.GameName ) {
        vars.DebugOutput("Game in Livesplit changed, reinitialising...");
        vars.gamename = timer.Run.GameName;
        vars.reInitialise();
    }
    vars.watchers.UpdateAll(game);

    var start = false;
    var split = false;
    var reset = false;

    if ( vars.ingame && ( vars.isGenSonic1or2 || vars.isS3K || vars.isSonicCD ) ) {
        current.scoretally = vars.watchers["scoretally"].Current;
        current.timebonus = vars.watchers["timebonus"].Current;
        if ( vars.isBigEndian ) {
            current.scoretally = vars.SwapEndianness(vars.watchers["scoretally"].Current);
            current.timebonus  = vars.SwapEndianness(vars.watchers["timebonus"].Current);
        }

        if ( current.timebonus > 999 ) {
            current.hascontinue = true;
        }
        if ( timer.CurrentPhase == TimerPhase.Paused && old.timebonus == 0 ) {
            
            
            if (vars.isGenSonic1or2 && !vars.isGenSonic1 && current.hascontinue && vars.stopwatch.ElapsedMilliseconds < 2000) {
                if ( vars.stopwatch.ElapsedMilliseconds == 0) {
                    vars.stopwatch.Start();
                }
            } else {
                // If we had a bonus, and the previous frame's timebonus is now 0, reset it
                vars.loading = false;
                current.hascontinue = false;
                vars.stopwatch.Reset();
                // pause to unpause LUL
                vars.timerModel.Pause();
            }

        } else if ( !vars.loading && vars.watchers["act"].Current <= 2 && current.timebonus < old.timebonus && current.scoretally > old.scoretally ) {
            // if we haven't detected a bonus yet
            // check that we are in an act (sanity check)
            // then check to see if the current timebonus is less than the previous frame's one.
            vars.DebugOutput(String.Format("Detected Bonus decrease: {0} from: {1}", current.timebonus, old.timebonus));
            vars.loading = true;
            vars.timerModel.Pause();
            
        }
    }


    if ( vars.splitInXFrames == 0 ) {
        vars.splitInXFrames = -1;
        split = true;
    } else if ( vars.splitInXFrames > 0 ) {
        vars.splitInXFrames--;
    }



    if ( !vars.ingame && timer.CurrentPhase == TimerPhase.Running) {
        //pressed start run or autostarted run
        
        vars.DebugOutput("run start detected");
        vars.igttotal = 0;
        vars.ms = 0;
        vars.ingame = true;
        if ( vars.isGenSonic1or2 ) {
            vars.loading = true;
        }
        if ( vars.isSonicCD ) {
            current.totalseconds = 0;
            vars.waitforminutes = 0;
            vars.waitforseconds = 0;
            vars.waitforframes = 0;
            vars.wait = false;
        }
        if ( vars.isS3K ) {
            if ( vars.nextzone != 7 ) {
                vars.nextzone = 0;
            }
            vars.nextact = 1;
            vars.dez2split = false;
            vars.ddzsplit = false;
            vars.sszsplit = false;
            vars.bonus = false;
            vars.savefile = vars.watchers["savefile"].Current;
            vars.skipsAct1Split = !settings["actsplit"];
        }
        
    } else if ( vars.ingame && !( timer.CurrentPhase == TimerPhase.Running || timer.CurrentPhase == TimerPhase.Paused ) ) {
        vars.DebugOutput("run stop detected");
        vars.ingame = false;
        return false;
    }


    var gametime = TimeSpan.FromDays(999);
    var oldgametime = gametime;
    if ( vars.isSMSGGSonic2 && vars.watchers["systemflag"].Current == 1 ) {
        vars.levelselectbytes = new byte[] { 0xB6 };
    }
    if ( (long) vars.levelselectoffset > 0 && settings["levelselect"] && vars.watchers["levelselect"].Current != vars.levelselectbytes[0] ) {
        vars.DebugOutput("Enabling Level Select");
        
        game.WriteBytes( (IntPtr) vars.levelselectoffset, (byte[]) vars.levelselectbytes );
    }

    switch ( (string) vars.gamename ) {
        /**********************************************************************************
            ANCHOR START Alex Kidd in Miracle World Support
        **********************************************************************************/
        case "Alex Kidd in Miracle World":
            if ( !vars.ingame && vars.watchers["level"].Current == 1 && vars.watchers["trigger"].Current == 1 ) {
                // Have control so start timer
                start = true;
                vars.nextsplit = 2;
            }

            if ( vars.ingame ) {
                if ( (
                    vars.watchers["level"].Current == vars.nextsplit
                    ) ||
                    vars.watchers["level"].Current == 17 && vars.watchers["complete"].Current ==1
                ) {
                    vars.nextsplit++;
                    // Have control so start timer
                    split = true;
                }
                if ( vars.watchers["lives"].Current == 0 && vars.watchers["level"].Current == 0) {
                    reset = true;
                }
            }
            break;
        /**********************************************************************************
            ANCHOR START Sonic 3D Blast Support
        **********************************************************************************/
        case "Sonic 3D Blast":
            if(!((IDictionary<String, object>)old).ContainsKey("igt")) {
                old.igt = vars.watchers["levelframecount"].Old;
            }
            var lfc = vars.watchers["levelframecount"].Current;
            if ( vars.isBigEndian ) {
                lfc = vars.SwapEndianness(lfc);
            }
            current.igt = Math.Floor(Convert.ToDouble(lfc / 60) );

            if ( current.igt == old.igt + 1) {
                vars.igttotal++;
            }
            current.timerPhase = timer.CurrentPhase;

            if ( vars.watchers["emeralds"].Current != vars.watchers["emeralds"].Old ) {
                vars.DebugOutput(String.Format("Emeralds: {0}", vars.watchers["emeralds"].Current));
            }

            if ( !vars.ingame && vars.watchers["ingame"].Current == 1 && vars.watchers["ingame"].Old == 0 && vars.watchers["level"].Current <= 1 ) {
                start = true;
            }

            if (vars.watchers["ingame"].Current == 0 && vars.watchers["ingame"].Old == 1 && vars.watchers["level"].Current == 0 ) {
                reset = true;
            }
            if ( vars.watchers["level"].Current > 1 && vars.watchers["level"].Current == (vars.watchers["level"].Old + 1)  // Level Change
            ) {
                split = true;
            }
            if ( 
                ( vars.watchers["level"].Current == 21 && vars.watchers["emeralds"].Current < 7 && vars.watchers["ppboss"].Old == 224 && vars.watchers["ppboss"].Current == 128) || // Panic Puppet Boss Destroyed
                ( vars.watchers["level"].Current == 22 && vars.watchers["ffboss"].Old == 1 && vars.watchers["ffboss"].Current == 0) // Final Fight Boss
            ) {
                vars.bossdown = true;
            }
            if (
                vars.bossdown &&
                vars.watchers["fadeout"].Current == 0 && vars.watchers["fadeout"].Old != 0
            ) {
                split = true;
            }


            gametime = TimeSpan.FromSeconds(vars.igttotal);
            break;
        /**********************************************************************************
            ANCHOR START Sonic Spinball (Genesis / Mega Drive) 
        **********************************************************************************/
        case "Sonic Spinball (Genesis / Mega Drive)":
            var menutimeout = vars.watchers["menutimeout"].Old;
            if ( vars.isBigEndian ) {
                menutimeout = vars.SwapEndianness( menutimeout );
            }
            if ( vars.watchers["menuoption"].Old == 15 || vars.watchers["menuoption"].Old == 1 || vars.watchers["menuoption"].Old == 2 ) {
                vars.lastmenuoption = vars.watchers["menuoption"].Old;
            }
            if ( !vars.ingame && 
                 (
                     vars.lastmenuoption == 15 ||
                     vars.lastmenuoption == 1
                 )
                 &&
                 vars.watchers["gamemode"].Current == 0 &&
                 menutimeout > 10 &&
                
                vars.watchers["trigger"].Old == 3 &&
                vars.watchers["trigger"].Current == 2 ) {
                start = true;
            } else {
                if (
                        // Died
                        vars.watchers["gamemode"].Old == 2 &&
                        vars.watchers["gamemode"].Current == 6
                ) {
                    vars.skipsplit = true;
                }
                
                if (
                    (
                        // Level -> Boss Destroyed
                        vars.watchers["gamemode"].Old == 2 &&
                        vars.watchers["gamemode"].Current == 4
                        
                    ) ||
                    (
                        // Bonus Stage -> Level
                        vars.watchers["gamemode"].Old == 6 &&
                        vars.watchers["gamemode"].Current == 1
                        
                    ) || 
                    (
                        settings["ss_multiball"] &&
                        (
                            (
                                vars.watchers["gamemode"].Old == 2 &&
                                vars.watchers["gamemode"].Current == 3
                            ) ||
                            (
                                vars.watchers["gamemode"].Old == 3 &&
                                vars.watchers["gamemode"].Current == 2
                            )
                        )
                    )
                
                ) {
                    if ( vars.skipsplit ) {
                        vars.skipsplit = false;
                    } else {
                        split = true;
                    }
                }
                if (
                    vars.watchers["gamemode"].Current == 0 &&
                    vars.watchers["gamemode"].Old > 0 &&
                    vars.watchers["gamemode"].Old <= 6
                ) {
                    reset = true;
                }
            }
            break;
        /**********************************************************************************
            ANCHOR START Sonic the Hedgehog 1 & 2 Genesis & 2 8 bit support
        **********************************************************************************/
        case "Sonic the Hedgehog (Genesis / Mega Drive)":
        case "Sonic the Hedgehog 2 (Genesis / Mega Drive)":
        case "Sonic the Hedgehog 2 (Game Gear / Master System)":
        case "Sonic Chaos":
        case "Sonic CD":
            if ( !vars.ingame && 
                ( 
                    ( !vars.isSonicChaos && vars.watchers["trigger"].Current == vars.startTrigger && ( !vars.isSonicCD || vars.watchers["timeperiod"].Current == 1   ) ) ||
                    ( vars.isSonicChaos && ( vars.watchers["lives"].Old == 0 && vars.watchers["lives"].Current >= 3 ) )
                 ) && 
                vars.watchers["act"].Current == 0 && 
                vars.watchers["zone"].Current == 0 
            ) {
                vars.nextsplit = "0-1"; // 2nd Level
                start = true;
                vars.igttotal = 0;
                
            }
            if ( settings["s2smsallemeralds"] && vars.isSMSGGSonic2 ) {
                // enable all emeralds
                if ( vars.watchers["emeraldcount"].Current < vars.watchers["zone"].Current ) {
                    vars.DebugOutput("Updating Emerald Count");
                    game.WriteBytes( (IntPtr) vars.emeraldcountoffset, new byte[] { vars.watchers["zone"].Current } );
                }
                if ( vars.watchers["zone"].Current == 5 && vars.watchers["emeraldflags"].Current < 0x1F ) {
                    vars.DebugOutput("Updating Emerald Flags");
                    game.WriteBytes( (IntPtr) vars.emeraldflagsoffset, new byte[] { 0x1F } );
                }
                if ( vars.watchers["zone"].Current == 6 && vars.watchers["emeraldflags"].Current < 0x3F ) {
                    vars.DebugOutput("Updating Emerald Flags");
                    game.WriteBytes( (IntPtr) vars.emeraldflagsoffset, new byte[] { 0x3F } );
                }
            }
            if ( 
                !settings["levelselect"] && !vars.isSonicCD &&
                (
                    (  vars.watchers["lives"].Current == 0 && vars.watchers["continues"].Current == 0 ) ||
                    ( !vars.isSMSGGSonic2 && vars.watchers["trigger"].Current == 0x04 && vars.watchers["trigger"].Old == 0x0 ) 
                )
            ) {
                reset = true;
            }
            var currentlevel = String.Format("{0}-{1}", vars.watchers["zone"].Current, vars.watchers["act"].Current);
            if ( vars.nextsplit == currentlevel ) {
                vars.nextsplit = vars.expectednextlevel[currentlevel];
                vars.DebugOutput("Next Split on: " + vars.nextsplit);
                split = true;
                if ( vars.isSonicCD ) {
                    vars.igttotal += old.expectedms;
                    vars.ms = 0;
                    vars.loading = true;
                }
                
            }
            if ( vars.isSMSGGSonic2 && currentlevel == "7-0" && vars.nextsplit == "6-0") {
                split = true;
            }
            if ( vars.isSonicChaos && currentlevel == "5-2" && vars.watchers["endBoss"].Current == 255 && vars.splitInXFrames == -1) {
                vars.splitInXFrames = 3;
            }
            if ( 
                vars.nextsplit == "99-0" && (
                    ( vars.isGenSonic1 && vars.watchers["trigger"].Current == 0x18 ) ||
                    ( vars.isSonicCD && 
                        (vars.watchers["fadeout"].Current == 0xEE0EEE0EEE0EEE0E && vars.watchers["fadeout"].Old == 0xEE0EEE0EEE0EEE0E) ||
                        (vars.watchers["fadeout"].Current == 0x0EEE0EEE0EEE0EEE && vars.watchers["fadeout"].Old == 0x0EEE0EEE0EEE0EEE)
                    ) ||
                    ( !vars.isGenSonic1 && vars.watchers["trigger"].Current == 0x20 )
                    
                )
            )  {
                split = true;
            }

            if ( !vars.isIGT ) {
                break;
            }

            if ( vars.isSonicCD ) {
                if ( 
                    vars.loading &&
                    vars.watchers["minutes"].Current == vars.watchers["timewarpminutes"].Current &&
                    vars.watchers["seconds"].Current == vars.watchers["timewarpseconds"].Current &&
                    vars.watchers["framesinsecond"].Current == vars.watchers["timewarpframesinsecond"].Current
                
                ) {

                    vars.loading = false;
                }

                if (
                ( vars.watchers["timewarpminutes"].Current > 0 && vars.watchers["timewarpminutes"].Current != vars.watchers["timewarpminutes"].Old ) ||
                ( vars.watchers["timewarpseconds"].Current > 0 && vars.watchers["timewarpseconds"].Current != vars.watchers["timewarpseconds"].Old ) ||
                ( vars.watchers["timewarpframesinsecond"].Current > 0 && vars.watchers["timewarpframesinsecond"].Current != vars.watchers["timewarpframesinsecond"].Old ) 
                ) {
                    vars.waitforminutes = vars.watchers["timewarpminutes"].Current;
                    vars.waitforseconds = vars.watchers["timewarpseconds"].Current;
                    vars.waitforframes = vars.watchers["timewarpframesinsecond"].Current;
                    vars.wait = true;
                }
            }
            if ( vars.ingame && !vars.loading ) {
                if ( vars.isSonicCD ) {
                    
                    current.totalseconds = ( vars.watchers["minutes"].Current * 60) + vars.watchers["seconds"].Current;

                    vars.igttotal += Math.Max(current.totalseconds - old.totalseconds,0) * 1000;
                    current.expectedms = Math.Floor(vars.watchers["framesinsecond"].Current * (100.0/6.0));

                    vars.ms = current.expectedms;

                    if ( vars.wait && vars.waitforframes == vars.watchers["framesinsecond"].Current && vars.waitforseconds ==  vars.watchers["seconds"].Current && vars.waitforminutes == vars.watchers["minutes"].Current ) {
                        vars.wait = false;
                        vars.loading = true;
                    }
                    if ( vars.watchers["lives"].Current == vars.watchers["lives"].Old -1 ) {
                        vars.igttotal += vars.ms;
                        vars.ms = 0;
                        vars.loading = true;
                    }
                } else {
                    var oldSeconds = vars.watchers["seconds"].Old;
                    var curSeconds = vars.watchers["seconds"].Current;
                    if ( !vars.isGenSonic1or2 ) {
                        oldSeconds = ( ( oldSeconds >> 4 ) * 10 ) + ( oldSeconds & 0xF );
                        curSeconds = ( ( curSeconds >> 4 ) * 10 ) + ( curSeconds & 0xF );
                    }
                    if (
                        (
                            vars.watchers["minutes"].Current == vars.watchers["minutes"].Old &&
                            curSeconds == oldSeconds + 1
                        ) || (
                            vars.watchers["minutes"].Current == (vars.watchers["minutes"].Old + 1) &&
                            vars.watchers["seconds"].Current == 0 
                        )
                    ) {
                        vars.igttotal++;
                    }
                }
            } else if ( vars.loading && vars.watchers["levelframecount"].Current == 0 && 
                (
                    ( vars.isSonicCD && vars.watchers["levelframecount"].Old > 0 ) ||
                    ( vars.watchers["seconds"].Current == 0 && vars.watchers["minutes"].Current == 0 )
                ) ) {
                 vars.loading = false; //unpause timer once game time has reset
            }
            else if ( 
                vars.isSMSGGSonic2 && 
                vars.watchers["seconds"].Current == 1 && 
                vars.watchers["minutes"].Current == 0 &&
                vars.nextsplit != "0-1" ) {
                // handle Sonic 2 SMS shitty stuff
                vars.loading = false;
                vars.igttotal++;
            }
            if ( start || split ) {
                // pause to wait until the stage actually starts, to fix S1 issues like SB3->FZ
                vars.loading = !vars.isSonicChaos;
            }
            if ( vars.isSonicCD ) {
                gametime = TimeSpan.FromMilliseconds(vars.igttotal + vars.ms);
            } else {
                gametime = TimeSpan.FromSeconds(vars.igttotal);
            }
            
            break;
        /**********************************************************************************
            ANCHOR START Sonic the Hedgehog 3 & Knuckles split code
        **********************************************************************************/
            case "Sonic 3 & Knuckles":
                if (!vars.ingame && vars.watchers["trigger"].Current == 0x8C && vars.watchers["act"].Current == 0 && (vars.watchers["zone"].Current == 0 || vars.watchers["zone"].Current == 7 ) )
                {
                    vars.nextzone = vars.watchers["zone"].Current;
                    vars.DebugOutput(String.Format("next split on: zone: {0} act: {1}", vars.nextzone, vars.nextact));
                    start = true;
                }
                current.inMenu = ( vars.watchers["waterlevel"].Current == 0 && vars.watchers["centiseconds"].Current == 0 && vars.watchers["centiseconds"].Old == 0 );



                if ( vars.ingame ) {
                    // detecting memory checksum at end of RAM area being 0 - only changes if ROM is reloaded (Hard Reset)
                    // or if "DEL" is selected from the save file select menu.

                    if ( ( settings["hard_reset"] && vars.watchers["reset"].Current == 0 && vars.watchers["reset"].Old != 0 ) || 
                        ( current.inMenu == true
                            && ( 
                                ( vars.watchers["savefile"].Current == 9 && vars.watchers["delactive"].Current == 0xFF && vars.watchers["delactive"].Old == 0 ) ||
                                ( 
                                    vars.watchers["savefile"].Current == vars.savefile && 
                                    (vars.nextact + vars.nextzone) <= 1 && 
                                    vars.watchers["savefilezone"].Old == 255 && 
                                    vars.watchers["savefilezone"].Current == 0 )
                            )
                        ) ||
                        ( vars.isSK && vars.watchers["act"].Current == 0 && vars.watchers["zone"].Current == 0 )
                    ) {
                        reset = true;
                    }

                }
                const byte ACT_1 = 0;
                const byte ACT_2 = 1;

                const byte SONIC_AND_TAILS = 0;
                const byte SONIC = 1;
                const byte TAILS = 2;
                const byte KNUCKLES = 3;

                /* S3K levels */
                const byte ANGEL_ISLAND      = 0;
                const byte HYDROCITY         = 1;
                const byte MARBLE_GARDEN     = 2;
                const byte CARNIVAL_NIGHT    = 3;
                const byte ICE_CAP           = 5;
                const byte LAUNCH_BASE       = 6;
                const byte MUSHROOM_HILL     = 7;
                const byte FLYING_BATTERY    = 4;
                const byte SANDOPOLIS        = 8;
                const byte LAVA_REEF         = 9;
                const byte SKY_SANCTUARY     = 10;
                const byte DEATH_EGG         = 11;
                const byte DOOMSDAY          = 12;
                const byte LRB_HIDDEN_PALACE = 22;
                const byte DEATH_EGG_BOSS    = 23;

                if (!vars.nextzonemap.GetType().IsArray) {
                    vars.nextzonemap = new byte[] { 
                    /*  0 ANGEL_ISLAND      -> */ HYDROCITY, 
                    /*  1 HYDROCITY         -> */ MARBLE_GARDEN, 
                    /*  2 MARBLE_GARDEN     -> */ CARNIVAL_NIGHT, 
                    /*  3 CARNIVAL_NIGHT    -> */ ICE_CAP, 
                    /*  4 FLYING_BATTERY    -> */ SANDOPOLIS, 
                    /*  5 ICE_CAP           -> */ LAUNCH_BASE, 
                    /*  6 LAUNCH_BASE       -> */ MUSHROOM_HILL, 
                    /*  7 MUSHROOM_HILL     -> */ FLYING_BATTERY, 
                    /*  8 SANDOPOLIS        -> */ LAVA_REEF, 
                    /*  9 LAVA_REEF         -> */ LRB_HIDDEN_PALACE, 
                    /* 10 SKY_SANCTUARY     -> */ DEATH_EGG, 
                    /* 11 DEATH_EGG         -> */ DEATH_EGG_BOSS,
                    /* 12 DOOMSDAY          -> */ 0,
                    /* 13,14,15,16,17,18,19,20,21 */ 0,0,0,0,0,0,0,0,0,
                    /* 22 LRB_HIDDEN_PALACE -> */ SKY_SANCTUARY,
                    /* 23 DEATH_EGG_BOSS    -> */ DOOMSDAY
                    };
                }

                if ( vars.watchers["zone"].Old != vars.watchers["zone"].Current && settings["actsplit"] ) {
                    vars.skipsAct1Split = ( 
                        ( vars.watchers["zone"].Current == MARBLE_GARDEN && settings["act_mg1"] ) || 
                        ( vars.watchers["zone"].Current == ICE_CAP && settings["act_ic1"] ) ||
                        ( vars.watchers["zone"].Current == LAUNCH_BASE && settings["act_lb1"] )
                    );
                }

                if (
                    !vars.processingzone && 
                    vars.watchers["zone"].Current != DOOMSDAY && 
                    /* Make doubly sure we are in the correct zone */
                    vars.watchers["zone"].Current == vars.nextzone && vars.watchers["zone"].Old == vars.nextzone &&
                    vars.watchers["act"].Current == vars.nextact && vars.watchers["act"].Old == vars.nextact 
                ) {
                    vars.processingzone = true;
                    

                    switch ( (int)vars.watchers["act"].Current ) {
                        // This is AFTER a level change.
                        case ACT_1:
                            vars.nextact = ACT_2;
                            if ( 
                                // Handle IC boss skip and single act zones.
                                ( vars.watchers["zone"].Current == ICE_CAP && vars.skipsAct1Split ) ||
                                ( vars.watchers["zone"].Current == SKY_SANCTUARY ) ||
                                ( vars.watchers["zone"].Current == LRB_HIDDEN_PALACE )
                            ) {  
                                vars.nextzone = vars.nextzonemap[vars.watchers["zone"].Current];
                                vars.nextact = ACT_1;
                            }
                            split = ( vars.watchers["zone"].Current < LRB_HIDDEN_PALACE );
                            break;
                        case ACT_2:
                            // next split is generally Act 1 of next zone
                            vars.nextzone = vars.nextzonemap[vars.watchers["zone"].Current];
                            vars.nextact = ACT_1;
                            if ( vars.watchers["zone"].Current == LAVA_REEF || 
                                ( vars.watchers["zone"].Current == LRB_HIDDEN_PALACE && vars.watchers["chara"].Current == KNUCKLES ) 
                            ) {
                                // LR2 -> HP = 22-1 and HP -> SS2 for Knux
                                vars.nextact = ACT_2; 
                            }
                            // If we're not skipping the act 1 split, or we entered Hidden Palace
                            split = ( !vars.skipsAct1Split || vars.watchers["zone"].Current == LRB_HIDDEN_PALACE );

                            break;
                    }

                    vars.processingzone = false;
                }
                
                if (!vars.dez2split && vars.watchers["zone"].Current == DEATH_EGG_BOSS && vars.watchers["act"].Current == ACT_1) //detect fade to white on death egg 2
                {
                    if ((vars.watchers["dez2end"].Current == 0xEE0EEE0EEE0EEE0E && vars.watchers["dez2end"].Old == 0xEE0EEE0EEE0EEE0E) ||
                        (vars.watchers["dez2end"].Current == 0x0EEE0EEE0EEE0EEE && vars.watchers["dez2end"].Old == 0x0EEE0EEE0EEE0EEE))
                    {
                        vars.DebugOutput("DEZ2 Boss White Screen detected");
                        vars.dez2split = true;
                        split = true;
                    }
                }
                
                if (vars.watchers["zone"].Current == DOOMSDAY && vars.watchers["ddzboss"].Current == 255 && vars.watchers["ddzboss"].Old == 0) //Doomsday boss detect final hit
                {
                    vars.DebugOutput("Doomsday Zone Boss death detected"); //need to detect fade to white, same as DEZ2End
                    vars.ddzsplit = true;
                }
                
                if (vars.ddzsplit || vars.sszsplit) //detect fade to white on doomsday
                {
                    if ((vars.watchers["dez2end"].Current == 0xEE0EEE0EEE0EEE0E && vars.watchers["dez2end"].Old == 0xEE0EEE0EEE0EEE0E) ||
                        (vars.watchers["dez2end"].Current == 0x0EEE0EEE0EEE0EEE && vars.watchers["dez2end"].Old == 0x0EEE0EEE0EEE0EEE))
                    {
                        vars.DebugOutput("Doomsday/SS White Screen detected");
                        split = true;
                    }
                }
                

                if (vars.watchers["chara"].Current == KNUCKLES && vars.watchers["zone"].Current == SKY_SANCTUARY) //detect final hit on Knux Sky Sanctuary Boss
                {
                    if (vars.watchers["sszboss"].Current == 0 && vars.watchers["sszboss"].Old == 1)
                    {
                        vars.DebugOutput("Knuckles Final Boss 1st phase defeat detected");
                        vars.sszsplit = true;
                    }
                }
                
                if (split)
                {
                    vars.DebugOutput(String.Format("old level: {0:X4} old zone: {1} old act: {2}", vars.watchers["level"].Old, vars.watchers["zone"].Old, vars.watchers["act"].Old));
                    vars.DebugOutput(String.Format("level: {0:X4} zone: {1} act: {2}", vars.watchers["level"].Current, vars.watchers["zone"].Current, vars.watchers["act"].Current));
                    vars.DebugOutput(String.Format("next split on: zone: {0} act: {1}", vars.nextzone, vars.nextact));
                }
            break;
        /**********************************************************************************
            ANCHOR START Sonic the Hedgehog (Master System) support
        **********************************************************************************/
        case "Sonic the Hedgehog (Master System)":
            if ( vars.watchers["menucheck1"].Current == 5 && vars.watchers["menucheck1"].Old <= 1 && vars.watchers["menucheck2"].Current == 4 && vars.watchers["menucheck2"].Old <= 1 ) {
                reset = true;
            }

            if ( !vars.ingame && vars.watchers["state"].Old == 128 && vars.watchers["state"].Current == 224 && vars.watchers["level"].Current == 0 && vars.watchers["input"].Current != 255) {
                vars.DebugOutput(String.Format("Split Start of Level {0}", vars.watchers["level"].Current));
                start = true;
            }
            if (
                (
                    (vars.watchers["level"].Current != vars.watchers["level"].Old && vars.watchers["level"].Current <= 17) || 
                    (vars.watchers["endBoss"].Current == 89 && vars.watchers["endBoss"].Old != 89 && vars.watchers["level"].Current==17)
                ) 
                && (vars.watchers["state"].Current != 0 && vars.watchers["level"].Current > 0)
            ) {
                vars.DebugOutput(String.Format("Split Start of Level {0}", vars.watchers["level"].Current));
                split = true;
            }
            
            if ( vars.loading && vars.watchers["timebonus"].Current == 0 ) {
                vars.loading = false;
            } else if ( !vars.loading && vars.watchers["timebonus"].Current > 0 && vars.watchers["scorescreen"].Current == 27 && vars.watchers["scorescd"].Current == 22 ) {
                vars.loading = true;
            }
            break;



        default:
            break;
    }


    current.start = start;
    current.reset = reset;
    current.split = split;
    if ( gametime != oldgametime ) {
        current.gametime = gametime;
    }

}





startup
{
    vars.timerModel = new TimerModel { CurrentState = timer };
    string logfile = Directory.GetCurrentDirectory() + "\\SEGAMasterSplitter.log";
    if ( File.Exists( logfile ) ) {
        File.Delete( logfile );
    }


    Func<ushort,ushort> SwapEndianness = (ushort value) => {
        var b1 = (value >> 0) & 0xff;
        var b2 = (value >> 8) & 0xff;

        return (ushort) (b1 << 8 | b2 << 0);
    };

    vars.LookUp = (Func<Process, SigScanTarget, IntPtr>)((proc, target) =>
    {
        vars.DebugOutput("Scanning memory");

        IntPtr result = IntPtr.Zero;
        foreach (var page in proc.MemoryPages())
        {
            var scanner = new SignatureScanner(proc, page.BaseAddress, (int)page.RegionSize);
            if ((result = scanner.Scan(target)) != IntPtr.Zero)
                break;
        }

        return result;
    });

    vars.LookUpInDLL = (Func<Process, ProcessModuleWow64Safe, SigScanTarget, IntPtr>)((proc, dll, target) =>
    {
        vars.DebugOutput("Scanning memory");

        IntPtr result = IntPtr.Zero;
        var scanner = new SignatureScanner(proc, dll.BaseAddress, (int)dll.ModuleMemorySize);
        result = scanner.Scan(target);
        return result;
    });


    vars.BizHawksetup = (Func<Process, Process, long>)((thegame, mem) => {
            long memoryOffset = 0;
            long scanOffset = 0;
            long injectionMem = (long) thegame.AllocateMemory( 0x70 );
            SigScanTarget target;
            if ( thegame.Is64Bit() ) {
                vars.DebugOutput("64bit Bizhawk");
                /***************************
                * 64 bit Bizhawk
                ********************/
                target = new SigScanTarget(0, "53 48 83 EC 20 48 8B F1 41 8B F8 0F B7 DA 81 FB 00 C0 00 00 7C 25 48 8B 46 28 8B D3 81 E2 FF 1F 00 00 3B 50 08 0F 83 64 01 00 00");
                scanOffset = (long) vars.LookUp(thegame, target);
                if ( scanOffset != 0 ) {
                    vars.DebugOutput("Memory Found");
                } else {
                    Thread.Sleep(500);
                    throw new NullReferenceException (String.Format("BizHawk Memory not found. {0}", scanOffset ));
                    
                }
                
                
                var originalCode = new List<byte>() {
                    0x48, 0x8B, 0x46, 0x28,                     // mov rax,[rsi+28]
                    0x8B, 0xD3,                                 // mov edx,ebx
                    0x81, 0xE2, 0xFF, 0x1F, 0x00, 0x00,         // and edx,00001FFF
                    0x3B, 0x50, 0x08,                           // cmp edx,[rax+08]
                    0x0F, 0x83, 0x64, 0x01, 0x00, 0x00,         // jae SMS::WriteMemorySega+191 
                    0x48, 0x63, 0xD2                            // movsxd rdx, edx
                };

                var injectionCode = new List<byte>() {
                    0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
                    0x58,                                       // pop rax
                    0x48, 0x8B, 0x46, 0x28,                     // mov rax,[rsi+28]
                    0x48, 0xA3, /* injectionMem ref (17) */     // mov [injectionMem],rax
                    0x50,                                       // push rax
                    0x8B, 0xD3,                                 // mov edx,ebx
                    0x81, 0xE2, 0xFF, 0x1F, 0x00, 0x00,         // and edx,00001FFF
                    0x3B, 0x50, 0x08,                           // cmp edx,[rax+08]
                    0x72, 0x0C,                                 // jb
                    0x48, 0xB8,  /* scanOffset + 0x18F (33) */  // mov rax, [scanOffset + 0x18F]
                    0xFF, 0xE0,                                 // jmp rax
                    0x48, 0xB8,  /* scanOffset + 0x2A (37) */   // mov rax, [scanOffset + 0x2A]
                    0xFF, 0xE0,                                 // jmp rax
                };


                injectionCode.InsertRange( 37, BitConverter.GetBytes( (long) scanOffset + 0x2A  ) );
                injectionCode.InsertRange( 33, BitConverter.GetBytes( (long) scanOffset + 0x18F ) );
                injectionCode.InsertRange( 17, BitConverter.GetBytes( (long) injectionMem       ) );

                thegame.Suspend();
                vars.DebugOutput("start praying...");


                var replacementjump = new List<byte>() {
                    0x50,                                       // push rax
                    0x48, 0xB8,  /* injectionMem + 0x0A (3) */  // mov rax, [injectionMem + 0x0A]
                    0xFF, 0xE0,                                 // jmp rax
                    0x90, 0x90, 0x90, 0x90,                     // nop x 8
                    0x90, 0x90, 0x90, 0x90,  
                    0x58,                                       // pop rax
                };
                replacementjump.InsertRange( 3, BitConverter.GetBytes( (long) injectionMem + 0x0A ) );
                vars.DebugOutput( String.Format( "To write (code injected at {0:X}): " + BitConverter.ToString( injectionCode.ToArray() ), (long) injectionMem ) );
                vars.DebugOutput( String.Format( "To write (replacement jump at {0:X}): " + BitConverter.ToString( replacementjump.ToArray() ), (long) scanOffset + 0x16 ) );
                
                mem.WriteBytes( new IntPtr(injectionMem), injectionCode.ToArray() );
                vars.DebugOutput(String.Format("Memory for injection written at: {0:X}", (long) injectionMem));
                mem.WriteBytes( new IntPtr(scanOffset + 0x16), replacementjump.ToArray() );
                
                
                thegame.Resume();
                
                var count = 0;
                vars.DebugOutput("Waiting for core to write to memory");
                long oldMemoryOffset = memoryOffset + 0x20;
                while ( oldMemoryOffset != memoryOffset ) {
                    if ( count > 1 ) {
                        oldMemoryOffset = memoryOffset;
                    }
                    Thread.Sleep(500);
                    memoryOffset = mem.ReadValue<long>(new IntPtr( injectionMem ) ) + 0x10;
                    count++;
                    if ( count > 50 ) {
                        throw new NullReferenceException (String.Format("Genesis/SMS Memory not found. {0}", memoryOffset ));
                    }
                }
                vars.DebugOutput("Writing back old code");
                thegame.Suspend();
                thegame.WriteBytes( new IntPtr( scanOffset + 0x16 ), originalCode.ToArray() );

                thegame.Resume();
            } else {
                /***************************
                * 32 bit Bizhawk
                ********************/
                vars.DebugOutput("32bit Bizhawk");
                target = new SigScanTarget(0, "55 8B EC 57 56 53 50 8B F1 8B 5D 08 0F B7 FA 81 FF 00 C0 00 00 7C 1C 8B C7 25 FF 1F 00 00 8B 56 28 3B 42 04 0F 83 38 01 00 00");
                scanOffset = (long) vars.LookUp( thegame, target );
                if ( scanOffset == 0) {
                    Thread.Sleep(500);
                    throw new NullReferenceException (String.Format("BizHawk Memory not found. {0}", (long) scanOffset ));
                    
                }
                var originalCode = new List<byte>() {
                    0x8B, 0xC7,                                 // mov eax,edi
                    0x25, 0xFF, 0x1F, 0x0, 0x0,                 // and eax,00001FFF
                    0x8B, 0x56, 0x28,                           // mov edx, [esi+28]
                };
                var injectionCode = new List<byte>() {
                    0x89, 0x15,                                 // mov [injectionMem + 0x15], edx
                    0xE9,  /* see right */                      // jmp ( scanOffset + 0x21 ) - ( injectionMem + 0x15 )
                    0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0, 0x0,
                };

                injectionCode.InsertRange( 0, originalCode );
                injectionCode.InsertRange( 13, BitConverter.GetBytes( ( (int) scanOffset + 0x21 ) - ( (int) injectionMem + 0x15 ) ) );
                injectionCode.InsertRange( 12, BitConverter.GetBytes( (int) injectionMem + 0x15 ) );

                thegame.Suspend();
                vars.DebugOutput("start praying...");

                var replacementjump = new List<byte>() {
                    0xE9, /* see right */               // jmp [injectionMem  - ( scanOffset + 0x1C )]
                    0x90, 0x90, 0x90, 0x90, 0x90,       // nop x 5
                };


                replacementjump.InsertRange( 1, BitConverter.GetBytes( ( (int) injectionMem ) - ( (int) scanOffset + 0x1C ) ) );

                thegame.WriteBytes( new IntPtr( injectionMem ), injectionCode.ToArray());
                thegame.WriteBytes( new IntPtr( scanOffset + 0x17 ), replacementjump.ToArray() );
                
                vars.DebugOutput(String.Format("Memory for injection written at: {0:X}", (int) injectionMem));
                vars.DebugOutput(String.Format("WriteSegaMemory Found at: {0:X}",  scanOffset ));
                thegame.Resume();
                
                var count = 0;
                vars.DebugOutput("Waiting for core to write to memory");
                long oldMemoryOffset = memoryOffset + 0x20;
                while ( oldMemoryOffset != memoryOffset ) {
                    if ( count > 1 ) {
                        oldMemoryOffset = memoryOffset;
                    }
                    Thread.Sleep(500);
                    memoryOffset = mem.ReadValue<long>( new IntPtr( injectionMem + 0x15 ) ) + 0x08;
                    count++;
                    if ( count > 50 ) {
                        throw new NullReferenceException (String.Format("Genesis/SMS Memory not found. {0}", memoryOffset ));
                    }
                }


                vars.DebugOutput("Writing back old code");
                thegame.Suspend();
                thegame.WriteBytes( new IntPtr( scanOffset + 0x17 ), originalCode.ToArray() );

                thegame.Resume();

            }
            return memoryOffset;

    });



    vars.SwapEndianness = SwapEndianness;

    refreshRate = 60;

    /* S3K settings */
    settings.Add("s3k", true, "Settings for Sonic 3 & Knuckles");
    settings.Add("actsplit", false, "Split on each Act", "s3k");
    settings.SetToolTip("actsplit", "If unchecked, will only split at the end of each Zone.");
    
    settings.Add("act_mg1", false, "Ignore Marble Garden 1", "actsplit");
    settings.Add("act_ic1", false, "Ignore Ice Cap 1", "actsplit");
    settings.Add("act_lb1", false, "Ignore Launch Base 1", "actsplit");

    settings.Add("hard_reset", true, "Reset timer on Hard Reset?", "s3k");
    
    settings.SetToolTip("act_mg1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");
    settings.SetToolTip("act_ic1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");
    settings.SetToolTip("act_lb1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");

    settings.SetToolTip("hard_reset", "If checked, a hard reset will reset the timer.");

    /* Sonic Spinball settings */
    settings.Add("ss", true, "Settings for Sonic Spinball (Genesis / Mega Drive)");
    settings.Add("ss_multiball", false, "Split on entry & exit of multiball stages", "ss");
    settings.SetToolTip("ss_multiball", "If checked, will split on entry and exit of extra bonus stages for Max Jackpot Bonus.");

    /* Debug Settings */
    settings.Add("debug", false, "Debugging Options");
    settings.Add("levelselect", false, "Enable Level Select (if supported)", "debug");
    settings.Add("s2smsallemeralds", false, "S2SMS Enable All Emeralds", "debug");

    Action<string> DebugOutput = (text) => {
        print("[SEGA Master Splitter] "+text);
        string time = System.DateTime.Now.ToString("dd/mm/yy hh:mm:ss:fff");
        File.AppendAllText(logfile, "[" + time + "]: " + text + "\r\n");
        
    };

    Action<ExpandoObject> DebugOutputExpando = (ExpandoObject dynamicObject) => {
            var dynamicDictionary = dynamicObject as IDictionary<string, object>;
         
            foreach(KeyValuePair<string, object> property in dynamicDictionary)
            {
                DebugOutput(String.Format("{0}: {1}", property.Key, property.Value.ToString()));
            }
            DebugOutput("");
    };



    vars.DebugOutput = DebugOutput;
    vars.DebugOutputExpando = DebugOutputExpando;
    

}


start
{
    if ( current.start ) {
        current.start = false;
        return true;
    }
}

reset
{
    if ( current.reset ) {
        current.reset = false;
        vars.ingame = false;
        return true;
    }
}

split
{
    if ( current.split ) {
        current.split = false;
        return true;
    }
    
}

isLoading
{
    if ( vars.isIGT ) {
        return true;
    }
    return vars.loading;
}

gameTime
{
    if ( !vars.isIGT ) {
        return TimeSpan.FromMilliseconds(timer.CurrentTime.GameTime.Value.TotalMilliseconds);
    }
    if(((IDictionary<String, object>)current).ContainsKey("gametime")) {
        return current.gametime;
    }
}
