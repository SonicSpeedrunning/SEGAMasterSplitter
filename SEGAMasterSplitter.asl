/*
    * SEGA Master Splitter
    Splitter designed to handle multiple 8 and 16 bit SEGA games running on various emulators
*/

state("retroarch") {}
state("Fusion") {}
//state("gens") {}
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
    long refLocation = 0;
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
                refLocation = ( (long ) codeOffset + 0x14 + memoryReference );
            } else {
                SigScanTarget target = new SigScanTarget(0, "8B 44 24 04 85 C0 74 18 83 F8 02 BA 00 00 00 00 B8 ?? ?? ?? ?? 0F 45 C2 C3 8D B4 26 00 00 00 00");
                IntPtr codeOffset = vars.LookUpInDLL( game, gpgx, target );
                refLocation = (long) codeOffset + 0x11;
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

    if ( game.ProcessName.ToLower().StartsWith("sega") ) {
        refLocation = (long) IntPtr.Add(baseAddress, (int)genOffset);
        genOffset = 0;
    } 
    if ( genOffset > 0 ) {
        refLocation = memory.ReadValue<int>(IntPtr.Add(baseAddress, (int)genOffset) );
    }
    vars.DebugOutput(String.Format("refLocation: {0}", refLocation));
    if ( refLocation > 0 ) {
        memoryOffset = memory.ReadValue<int>( (IntPtr) refLocation );
        if ( memoryOffset == 0 ) {
            memoryOffset = refLocation;
        }
    }

    vars.emuoffsets = new MemoryWatcherList
    {
        new MemoryWatcher<uint>(  (IntPtr) refLocation    ) { Name = "genesis", FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull },
        new MemoryWatcher<uint>(  (IntPtr) IntPtr.Add(baseAddress, (int)smsOffset)     ) { Name = "sms" },
        new MemoryWatcher<uint>(  (IntPtr) baseAddress    ) { Name = "baseaddress", FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull }
    };

    if ( memoryOffset == 0 && ( !isFusion || smsMemoryOffset == 0xC000 ) ) {
        throw new NullReferenceException (String.Format("Memory offset not yet found. Base Address: 0x{0:X}", (long) baseAddress ));
        Thread.Sleep(500);
    }


    vars.isBigEndian = isBigEndian;
    Action reInitialise = () => {
        vars.emuoffsets.UpdateAll(game);
        memoryOffset = vars.emuoffsets["genesis"].Current;
        if ( memoryOffset == 0 && refLocation > 0 ) {
            memoryOffset = refLocation;
        }
        smsMemoryOffset = memoryOffset;


        if ( isFusion ) {
            smsMemoryOffset = memory.ReadValue<int>(IntPtr.Add(baseAddress, (int)smsOffset) ) + (int) 0xC000;
        }
        vars.DebugOutput(String.Format("memory should start at {0:X}", memoryOffset));
        vars.DebugOutput(String.Format("SMS memory should start at {0:X}", smsMemoryOffset));
        vars.isIGT = false;
        current.loading = false;
        vars.igttotal = 0;

        vars.ingame = false;

        vars.levelselectoffset = 0;
        vars.isGenSonic1 = false;
        vars.isGenSonic1or2 = false;
        vars.isS3K = false;
        vars.isSK = false;
        vars.isS3 = false;
        vars.isS3KBonuses = false;
        vars.isSMSS1 = false;
        vars.isSMSGGSonic2 = false;
        vars.hasRTATB = false;
        vars.isSonicChaos = false;
        vars.isSonicCD = false;
        vars.nextsplit = "";
        vars.startTrigger = 0x8C;
        vars.splitInXFrames = -1;
        vars.bossdown = false;
        vars.juststarted = false;
        vars.triggerTB = false;
        vars.levelselectbytes = new byte[] {0x01}; // Default as most are 0 - off, 1 - on
        IDictionary<string, string> expectednextlevel = new Dictionary<string, string>();
        vars.expectedzonemap = false;
        vars.stopwatch = new Stopwatch();
        vars.timebonusms = 0;
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
                ANCHOR START Magical Taruruuto-kun watchlist
            **********************************************************************************/
            case "Magical Taruruuto-kun":
                vars.levelselectbytes = new byte[] {0xC0};
                vars.levelselectoffset = (IntPtr)memoryOffset + ( isBigEndian ? 0xFD31 : 0xFD30 );
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFD4B : 0xFD4A ) ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFEF9 : 0xFEF8 ) ) { Name = "gamemode" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xF806 : 0xF807 ) ) { Name = "menu" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xE19C : 0xE19C ) ) { Name = "clearelement" },
                    new MemoryWatcher<byte>(  vars.levelselectoffset ) { Name = "levelselect" },
                };
                break;


            /**********************************************************************************
                ANCHOR START Mystic Defender watchlist
            **********************************************************************************/
            case "Mystic Defender":
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xF627 : 0xF627 ) ) { Name = "stage" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xF629 : 0xF628 ) ) { Name = "level" },
                    new MemoryWatcher<ushort>(  (IntPtr)memoryOffset + 0xD010                          ) { Name = "menucheck" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xE61F : 0xE61E ) ) { Name = "bosshp" },
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
                ANCHOR START Sonic Eraser 
            **********************************************************************************/
            case "Sonic Eraser":
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xC711 : 0xC710 ) ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xBE23 : 0xBE24 ) ) { Name = "start" },
                };

                break;
            /**********************************************************************************
                ANCHOR START Sonic Spinball (Genesis / Mega Drive) 
            **********************************************************************************/
            case "Sonic Spinball":
            case "Sonic Spinball (Genesis / Mega Drive)":
                vars.gamename = "Sonic Spinball (Genesis / Mega Drive)";
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
                    new MemoryWatcher<ulong>( (IntPtr)memoryOffset + 0xFB00 ) { Name = "fadeout" },

                };
                vars.isGenSonic1or2 = true;
                vars.isIGT = true;
                vars.hasRTATB = true;

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
            case "Sonic 3 & Knuckles - Bonus Stages Only":
            case "Sonic & Knuckles - Bonus Stages Only":
            case "Sonic the Hedgehog 3":
            case "Sonic 3":

                vars.levelselectoffset = (IntPtr) memoryOffset + ( isBigEndian ? 0xFFE0 : 0xFFE1 );
                if ( vars.gamename == "Sonic 3" || vars.gamename == "Sonic the Hedgehog 3" ) {
                    vars.isS3 = true;
                    vars.levelselectoffset = (IntPtr) memoryOffset + ( isBigEndian ? 0xFFD0 : 0xFFD1 );
                }
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEE4E : 0xEE4F ) ) { Name = "zone", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEE4F : 0xEE4E ) ) { Name = "act", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + 0xFFFC ) { Name = "reset", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xF600 : 0xF601 ) ) { Name = "trigger" },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xF7D2 ) { Name = "timebonus", Enabled = false },
                    new MemoryWatcher<ushort>((IntPtr)memoryOffset + 0xFE28 ) { Name = "scoretally", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFF09 : 0xFF08 ) ) { Name = "chara", Enabled = false },
                    new MemoryWatcher<ulong>( (IntPtr)memoryOffset + 0xFC00) { Name = "primarybg", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xB1E5 : 0xB1E4 ) ) { Name = "ddzboss", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xB279 : 0xB278 ) ) { Name = "sszboss", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEEE4 : 0xEEE5 ) ) { Name = "delactive", Enabled = false },

                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xEF4B : 0xEF4A ) ) { Name = "savefile", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xFDEB : 0xFDEA ) ) { Name = "savefilezone", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + ( isBigEndian ? 0xB15F : 0xB15E ) ) { Name = "s3savefilezone", Enabled = false },
                    new MemoryWatcher<byte>(  vars.levelselectoffset     ) { Name = "levelselect" },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + 0xFFB0 ) { Name = "chaosemeralds", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset + 0xFFB1 ) { Name = "superemeralds", Enabled = false },
                    /* $FFA6-$FFA9  Level number in Blue Sphere  */ 
                    /* $FFB0 	Number of chaos emeralds  */ 
                    /* $FFB1 	Number of super emeralds  */ 
                    /* $FFB2-$FFB8 	Array of finished special stages. Each byte represents one stage: 
            
                        0 - special stage not completed 
                        1 - chaos emerald collected 
                        2 - super emerald present but grayed 
                        3 - super emerald present and activated  
                    */ 
                };
                vars.expectedzone = 0;
                vars.expectedact = 1;
                vars.sszsplit = false; //boss is defeated twice
                vars.savefile = 255;
                vars.skipsAct1Split = false;
                vars.isS3K = true;
                vars.specialstagetimer = new Stopwatch(); 
                vars.addspecialstagetime = false; 
                vars.specialstagetimeadded = false; 
                vars.gotEmerald = false;
                vars.chaoscatchall = false;
                vars.chaossplits = 0;
                vars.hasRTATB = true;
                if ( vars.gamename != "Sonic 3 & Knuckles - Bonus Stages Only" && vars.gamename != "Sonic & Knuckles - Bonus Stages Only" ) {
                    vars.gamename = "Sonic 3 & Knuckles";
                } else {
                    vars.isS3K = false;
                    vars.isS3KBonuses = true;
                    current.loading = true;
                    vars.hasRTATB = false;
                    if ( vars.gamename == "Sonic & Knuckles - Bonus Stages Only" ) {
                        vars.isSK = true;
                    }
                }
                
                break;
            /**********************************************************************************
                ANCHOR START Sonic the Hedgehog (Master System) watchlist
            **********************************************************************************/
            case "Sonic the Hedgehog (Master System)":
                vars.ringsoffset = (IntPtr)smsMemoryOffset +  0x12AA;
                vars.leveloffset = (IntPtr)smsMemoryOffset +  0x123E;
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(   vars.leveloffset   ) { Name = "level" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1000     ) { Name = "state" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1203     ) { Name = "input" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x12D5     ) { Name = "endBoss" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x122C     ) { Name = "scorescreen" },
                    new MemoryWatcher<uint>(  (IntPtr)smsMemoryOffset +  0x1212   ) { Name = "timebonus", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1C08   ) { Name = "menucheck1" },
                    new MemoryWatcher<byte>(  (IntPtr)smsMemoryOffset +  0x1C0A   ) { Name = "menucheck2" },
                };
                
                vars.hasRTATB = true;
                vars.isSMSS1 = true;
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
        /**********************************************************************************
            ANCHOR START Tiny Toon Adventures: Buster's Hidden Treasure watchlist
        **********************************************************************************/
            case "Tiny Toon Adventures: Buster's Hidden Treasure":
                vars.watchers = new MemoryWatcherList
                {
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xF92F : 0xF92E )    ) { Name = "menuoption"  },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xF90C : 0xF90D )    ) { Name = "inmenu"  },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xF907 : 0xF906 )    ) { Name = "trigger"  },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xF973 : 0xF973 )    ) { Name = "level", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xF01E : 0xF01F )    ) { Name = "roundcleartrigger" },
                    new MemoryWatcher<ushort>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xB7C0 : 0xB7C0 )    ) { Name = "roundclear", Enabled = false },
                    new MemoryWatcher<byte>(  (IntPtr)memoryOffset +   ( isBigEndian ? 0xF8FF : 0xF8FE )    ) { Name = "bosskill" },
                };
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
    const ulong WHITEOUT = 0x0EEE0EEE0EEE0EEE;
    if ( settings["levelselect"] && vars.watchers["levelselect"].Enabled == false ) {
        vars.watchers["levelselect"].Enabled = true;
    }


    uint changed = 0;
    string changednames = "";
    //vars.watchers.UpdateAll(game);
    foreach ( var watcher in vars.watchers ) {
        bool watcherchanged = watcher.Update(game);
        if ( watcherchanged ) {
            changed++;
            if ( settings["extralogging"] ) {
                changednames = changednames + watcher.Name + " ";
            }
        }
    }
    if ( vars.isSMSGGSonic2 && vars.watchers["systemflag"].Current == 1 ) {
        vars.levelselectbytes = new byte[] { 0xB6 };
    }
    bool lschanged = false;
    if ( (long) vars.levelselectoffset > 0 && settings["levelselect"] && vars.watchers["levelselect"].Current != vars.levelselectbytes[0] ) {
        vars.DebugOutput(String.Format("Enabling Level Select at {0:X8} with {1} because it was {2}", vars.levelselectoffset,  vars.levelselectbytes[0], vars.watchers["levelselect"].Current));
        
        game.WriteBytes( (IntPtr) vars.levelselectoffset, (byte[]) vars.levelselectbytes );
        lschanged = true;
    }
    if ( changed == 0 ) {
        vars.emuoffsets.UpdateAll(game);
        if ( vars.livesplitGameName != timer.Run.GameName || vars.emuoffsets["genesis"].Old != vars.emuoffsets["genesis"].Current || vars.emuoffsets["baseaddress"].Current != vars.emuoffsets["baseaddress"].Old ) {
            vars.DebugOutput("Game in Livesplit changed or memory address changed, reinitialising...");
            vars.gamename = timer.Run.GameName;
            vars.reInitialise();
        }
        return vars.stopwatch.IsRunning || lschanged;
    }
    if ( settings["extralogging"] ) {
        vars.DebugOutput(String.Format( "{0} things changed: " + changednames, changed ) );
    }
    var start = false;
    var split = false;
    var reset = false;

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
        vars.juststarted = false;
        current.timebonus = 0;
        current.scoretally = 0;
        if ( vars.isGenSonic1or2 ) {
            current.loading = true;
            current.hascontinue = false;
        }
        if ( vars.isSonicCD ) {
            current.totalseconds = 0;
            vars.waitforminutes = 0;
            vars.waitforseconds = 0;
            vars.waitforframes = 0;
            vars.wait = false;
        }
        if ( vars.isS3K || vars.isS3KBonuses ) {
            if ( vars.expectedzone != 7 ) {
                vars.expectedzone = 0;
            }
            vars.expectedact = 1;
            vars.sszsplit = false;
            vars.skipsAct1Split = !settings["actsplit"];
            vars.specialstagetimer = new Stopwatch(); 
            vars.addspecialstagetime = false;
            vars.specialstagetimeadded = false;
            vars.specialstagetimer.Reset();
            vars.gotEmerald = false;
            vars.chaoscatchall = false;
            vars.chaossplits = 0;
            if ( vars.isS3KBonuses ) {
                current.loading = true;
                vars.juststarted = true;
                vars.DebugOutput("S3K Bonuses");
            }
        }
        
    } else if ( vars.ingame && !( timer.CurrentPhase == TimerPhase.Running || timer.CurrentPhase == TimerPhase.Paused ) ) {
        vars.DebugOutput("run stop detected");
        vars.ingame = false;
        return false;
    }


    var gametime = TimeSpan.FromDays(999);
    var oldgametime = gametime;


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
            ANCHOR START Magical Taruruuto-kun Support
        **********************************************************************************/
        case "Magical Taruruuto-kun":
            if ( !vars.ingame && vars.watchers["gamemode"].Old == 1 && vars.watchers["gamemode"].Current == 1 && vars.watchers["level"].Current == 1) {
                start = true;
            }


            if ( vars.ingame ) {

                if ( vars.watchers["level"].Current == 67 && vars.watchers["clearelement"].Current == 2 ) {
                    split = true;
                }
                if ( vars.watchers["level"].Current > vars.watchers["level"].Old ) {
                    /*
                        Stages:
                        3 Honmaru (help?)
                        5 Harakko (autoscroller boss)
                        6 Jabao (footballer boss) Stage 1 boss
                        14 Ria (help?)
                        15 Mikotaku (boss)
                        19 Mimora (boss) Stage 2 boss
                        21 Door
                        22 vamp boss?
                        23 Ijigawa (help?)
                        26 Door
                        27 Shogunnosuke (help?)
                        31 Dowahha (boss) Stage 3 boss
                        33 Return of Harakko (autoscroller boss)
                        34 Demo
                        47 Nilulu (help?)
                        62 Ohaya (help?)
                        67 Rivar

                    */
                    if ( settings["mtk_before"] ) {
                        switch ( (int) vars.watchers["level"].Current ) {
                            case 6:
                            case 15:
                            case 19:
                            case 22:
                            case 31:
                            case 33:
                            case 67:
                                split = true;
                                break;
                        }
                    }
                    if ( settings["mtk_after"] ) {
                        switch ( (int) vars.watchers["level"].Old ) {
                            case 6:
                            case 15:
                            case 19:
                            case 22:
                            case 31:
                            case 33:
                                split = true;
                                break;
                        }
                    }
                    if ( vars.watchers["level"].Old == 67 ) {
                        split = true;
                    }


                }

                if ( vars.watchers["gamemode"].Current == 0 && vars.watchers["menu"].Old == 0 && vars.watchers["menu"].Current == 1) {
                    reset = true;
                }
            }

            break;
        /**********************************************************************************
            ANCHOR START Mystic Defender Support
        **********************************************************************************/
        case "Mystic Defender":
            current.menucheck = vars.watchers["menucheck"].Current;
            if ( vars.isBigEndian ) {
                current.menucheck = vars.SwapEndianness(current.menucheck);
            }
            if ( !vars.ingame && current.menucheck == 65535 && old.menucheck == 1 ) {
                // Have control so start timer
                start = true;
            }

            if ( vars.ingame ) {
                if (
                    ( vars.watchers["level"].Current > vars.watchers["level"].Old ) ||
                    ( vars.watchers["level"].Current == 14 && vars.watchers["bosshp"].Current == 0 && vars.watchers["bosshp"].Old > 0)
                ) {
                    // Have control so start timer
                    split = true;
                }
                if ( old.menucheck == 0 && current.menucheck == 1 ) {
                    reset = true;
                }
            }
            break;

        /**********************************************************************************
            ANCHOR START Tiny Toon Adventures: Buster's Hidden Treasure 
        **********************************************************************************/
        case "Tiny Toon Adventures: Buster's Hidden Treasure":
            //vars.DebugOutput( String.Format( "inmenu: {0}, menuoption: {1}, trigger: {2}, roundclear: {3}, bosskill: {4}", vars.watchers["inmenu"].Current, vars.watchers["menuoption"].Current, vars.watchers["trigger"].Current, vars.watchers["roundclear"].Current, vars.watchers["bosskill"].Current));
            if ( vars.watchers["inmenu"].Current == 0 && vars.watchers["inmenu"].Old == 1 && vars.watchers["menuoption"].Current == 0 && vars.watchers["trigger"].Old == 5 && vars.watchers["trigger"].Current == 6 ) {
                vars.watchers["roundclear"].Enabled  = false;
                start = true;

            }
            if ( vars.watchers["trigger"].Current == 5 &&  vars.watchers["trigger"].Old < 5 ) {
                reset = true;
            }
            //vars.DebugOutput(String.Format("Eh {0} {1}", vars.watchers["roundcleartrigger"].Current, vars.watchers["roundcleartrigger"].Old));
            if ( vars.watchers["roundcleartrigger"].Changed && vars.watchers["roundcleartrigger"].Current == 1 ) {
                vars.watchers["roundclear"].Enabled  = true;
                vars.watchers["roundclear"].Reset();
            }
            
            
            
            if ( 
                (
                    vars.watchers["trigger"].Current == 0 &&
                    vars.watchers["roundclear"].Enabled && vars.watchers["roundclear"].Old > 0 && vars.watchers["roundclear"].Current == 0
                ) || (
                    vars.watchers["bosskill"].Current == 1 && vars.watchers["bosskill"].Old == 0
                ) 
            ){
                vars.watchers["roundclear"].Enabled  = false;
                split = true;
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
            ANCHOR START Sonic Eraser
        **********************************************************************************/
        case "Sonic Eraser":

            if ( vars.watchers["start"].Old == 255 && vars.watchers["start"].Current == 1 ) {
                start = true;
            }

            if (vars.watchers["start"].Current == 255) {
                reset = true;
            }

            if ( vars.watchers["level"].Current > vars.watchers["level"].Old ) {
                split = true;
            }
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
                    current.loading = true;
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
                        (vars.watchers["fadeout"].Current == WHITEOUT && vars.watchers["fadeout"].Old == WHITEOUT)
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
                    current.loading &&
                    vars.watchers["minutes"].Current == vars.watchers["timewarpminutes"].Current &&
                    vars.watchers["seconds"].Current == vars.watchers["timewarpseconds"].Current &&
                    vars.watchers["framesinsecond"].Current == vars.watchers["timewarpframesinsecond"].Current
                
                ) {

                    current.loading = false;
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
            if ( vars.ingame && !current.loading ) {
                if ( vars.isSonicCD ) {
                    
                    current.totalseconds = ( vars.watchers["minutes"].Current * 60) + vars.watchers["seconds"].Current;

                    vars.igttotal += Math.Max(current.totalseconds - old.totalseconds,0) * 1000;
                    current.expectedms = Math.Floor(vars.watchers["framesinsecond"].Current * (100.0/6.0));

                    vars.ms = current.expectedms;

                    if ( vars.wait && vars.waitforframes == vars.watchers["framesinsecond"].Current && vars.waitforseconds ==  vars.watchers["seconds"].Current && vars.waitforminutes == vars.watchers["minutes"].Current ) {
                        vars.wait = false;
                        current.loading = true;
                    }
                    if ( vars.watchers["lives"].Current == vars.watchers["lives"].Old -1 ) {
                        vars.igttotal += vars.ms;
                        vars.ms = 0;
                        current.loading = true;
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
            } else if ( current.loading && vars.watchers["levelframecount"].Current == 0 && 
                (
                    ( vars.isSonicCD && vars.watchers["levelframecount"].Old > 0 ) ||
                    ( vars.watchers["seconds"].Current == 0 && vars.watchers["minutes"].Current == 0 )
                ) ) {
                 current.loading = false; //unpause timer once game time has reset
            }
            else if ( 
                vars.isSMSGGSonic2 && 
                vars.watchers["seconds"].Current == 1 && 
                vars.watchers["minutes"].Current == 0 &&
                vars.nextsplit != "0-1" ) {
                // handle Sonic 2 SMS shitty stuff
                current.loading = false;
                vars.igttotal++;
            }
            if ( start || split ) {
                // pause to wait until the stage actually starts, to fix S1 issues like SB3->FZ
                current.loading = !vars.isSonicChaos;
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
                const byte S3K_CREDITS       = 13;

                var trigger = vars.watchers["trigger"];
                var resettrigger = vars.watchers["reset"];
                var delactive = vars.watchers["delactive"];
                var zone = vars.watchers["zone"];
                var act = vars.watchers["act"];
                var primarybg = vars.watchers["primarybg"];
                if ( primarybg.Changed ) {
                    current.primarybg = primarybg.Current;
                    if ( vars.isBigEndian ) {
                        current.primarybg = vars.SwapEndiannessLong(primarybg.Current);
                    }
                }
                var savefile = vars.watchers["savefile"];
                var savefilezone = ( vars.isS3 ? vars.watchers["s3savefilezone"] : vars.watchers["savefilezone"] );

                if (!vars.expectedzonemap.GetType().IsArray) {
                    vars.expectedzonemap = new byte[] { 
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
                    /* 11 DEATH_EGG         -> */ DOOMSDAY,
                    /* 12 DOOMSDAY          -> */ S3K_CREDITS,
                    /* 13 S3K_CREDITS       -> */ 0,
                    /* 14,15,16,17,18,19,20,21 */ 0,0,0,0,0,0,0,0,
                    /* 22 LRB_HIDDEN_PALACE -> */ SKY_SANCTUARY,
                    /* 23 DEATH_EGG_BOSS    -> */ DOOMSDAY
                    };
                }

                if ( trigger.Changed ) {
                    if ( settings["extralogging"] ) {
                        vars.DebugOutput(String.Format("Trigger was: {0} now: {1}", trigger.Old, trigger.Current ) );
                    }
                    switch ( (int) trigger.Current ) {
                        case 0x00: // Game init - Disable all watchers except trigger.
                            foreach ( var watcher in vars.watchers ) {
                                if ( watcher.Name != "trigger" ) {
                                    watcher.Enabled = false;
                                    watcher.Reset();
                                }
                            }
                            current.primarybg  = 0;
                            break;
                        case 0x04: // sega logo -> title screen
                            zone.Enabled = true;
                            act.Enabled = true;
                            resettrigger.Enabled = settings["hard_reset"];
                            break;
                        case 0x4C: // data select screen
                            primarybg.Enabled = true;
                            savefile.Enabled = true;
                            savefilezone.Enabled = !vars.isSK;
                            delactive.Enabled = true;
                            break;
                        case 0x8C: // start game
                            vars.savefile = savefile.Current;
                            vars.DebugOutput(String.Format("Start game {0} {1} {2:X}", zone.Current, act.Current, trigger.Old) );

                            primarybg.Enabled = false;
                            savefilezone.Enabled = false;
                            savefile.Enabled = false;
                            delactive.Enabled = false;
                            zone.Enabled = true;
                            act.Enabled = true;
                            if ( !vars.ingame && act.Current == 0 && 
                                ( 
                                    ( zone.Current == 0 && trigger.Old == 0x4C ) ||
                                    ( vars.isSK && zone.Current == 7 && trigger.Old == 0x04 )
                                )
                            ) {
                                    vars.expectedzone = zone.Current;
                                    start = true;
                            }
                            break;
                        case 0x0C: // in level

                            vars.watchers["timebonus"].Enabled = true;
                            break;
                        case 0x34: // Go to special stage
                            current.loading = true;
                            if ( settings["pause_bs"] ) {
                                vars.specialstagetimer.Start();
                            }
                            vars.DebugOutput(String.Format("Detected Entering Special Stage"));
                            break;
                        case 0x48: // Special stage results screen
                            break;

                    }
                    if ( trigger.Old == 0x48 ) {
                        if ( vars.specialstagetimer.IsRunning ) {
                            vars.specialstagetimer.Stop(); 
                            vars.DebugOutput(String.Format("Time in Special Stage: {0}", vars.specialstagetimer.ElapsedMilliseconds));
                            current.loading = false;
                        }
                    }
                }


                // Reset triggers
                if ( 
                    // hard reset 
                    ( resettrigger.Changed && resettrigger.Current == 0 )
                    ||
                    // SK zone changed and set to 0.
                    ( vars.isSK && zone.Changed && act.Current == 0 && zone.Current == 0 ) ||
                    ( 
                        // in Menu
                        trigger.Current == 0x4C 
                        &&
                        (
                            // Delete selected on save screen
                            ( delactive.Changed && delactive.Current == 0xFF )
                            ||
                            // Checking savefile after reset
                            ( 
                                // Before Hydro 1 (0-0 AI1, 0-1 AI2, 1-0 HC1)
                                (vars.expectedact + vars.expectedzone) <= 1 &&
                                // Save file is the same
                                savefile.Current == vars.savefile &&
                                // Savefile zone = AI
                                savefilezone.Current == ANGEL_ISLAND &&
                                // Fading/Faded in
                                current.primarybg == 0xEE0ECC0AAA08 
                            )
                        )
                        
                    )
                ) {
                    reset = true;
                }

                if ( zone.Changed || act.Changed ) {
                    if ( !vars.watchers["timebonus"].Enabled ) {
                        vars.watchers["timebonus"].Enabled = true;
                    }
                    vars.DebugOutput(String.Format("Level change now: {0} {1} was: {2} {3} next split on: zone: {4} act: {5}", zone.Current, act.Current, zone.Old, act.Old, vars.expectedzone, vars.expectedact));
                    
                    if ( vars.expectedzone == DOOMSDAY && zone.Current == S3K_CREDITS ) {
                        vars.DebugOutput("S3K Credits Level detected, switching to wanting it as next level");
                        vars.expectedzone = S3K_CREDITS;
                        vars.expectedact = act.Current;
                    }
                    if ( 
                        /* Make doubly sure we are in the correct zone */
                        zone.Current == vars.expectedzone &&
                        act.Current == vars.expectedact
                    ) {
                        
                        if (
                             
                            (
                                (
                                    zone.Current == MUSHROOM_HILL &&
                                    act.Current == ACT_1
                                ) ||
                                (
                                    act.Current == ACT_2 &&
                                    zone.Current == LRB_HIDDEN_PALACE
                                )
                            ) &&
                            vars.specialstagetimer.ElapsedMilliseconds > 0
                        ) { 
                            vars.addspecialstagetime = true; 
                        } 
                        vars.skipsAct1Split =  settings["actsplit"] && ( 
                            ( zone.Current == MARBLE_GARDEN && settings["act_mg1"] ) || 
                            ( zone.Current == ICE_CAP && settings["act_ic1"] ) ||
                            ( zone.Current == LAUNCH_BASE && settings["act_lb1"] )
                        );
                        switch ( (int)act.Current ) {
                            // This is AFTER a level change.
                            case ACT_1:
                                vars.expectedact = ACT_2;
                                if ( 
                                    // Handle IC boss skip and single act zones.
                                    ( zone.Current == ICE_CAP && vars.skipsAct1Split ) ||
                                    ( zone.Current == SKY_SANCTUARY ) ||
                                    ( zone.Current == LRB_HIDDEN_PALACE )
                                ) {  
                                    vars.expectedzone = vars.expectedzonemap[zone.Current];
                                    vars.expectedact = ACT_1;
                                }
                                split = ( zone.Current < LRB_HIDDEN_PALACE );
                                break;
                            case ACT_2:

                                // next split is generally Act 1 of next zone
                                vars.expectedzone = vars.expectedzonemap[zone.Current];
                                vars.expectedact = ACT_1;
                                if ( zone.Current == LAVA_REEF || 
                                    ( zone.Current == LRB_HIDDEN_PALACE && vars.watchers["chara"].Current == KNUCKLES ) 
                                ) {
                                    // LR2 -> HP = 22-1 and HP -> SS2 for Knux
                                    vars.expectedact = ACT_2; 
                                }
                                // If we're not skipping the act 1 split, or we entered Hidden Palace
                                split = ( !vars.skipsAct1Split || zone.Current == LRB_HIDDEN_PALACE || zone.Current == S3K_CREDITS );
                                break;
                        }

                    }
                }
                vars.DebugOutput(String.Format("{0} {1} {2}", vars.isS3, zone.Current, act.Current ));
                if ( vars.sszsplit ||
                    ( vars.isS3 && zone.Current == LAUNCH_BASE && act.Current == ACT_2 )
                ) {
                    if ( !primarybg.Enabled )  {
                        primarybg.Enabled = true;
                        current.primarybg = (ulong) 0;
                        old.primarybg = (ulong)  0;
                    }
                    vars.DebugOutput(String.Format("{0:X} {1:X} {2:X} {3:X}", primarybg.Current, current.primarybg, old.primarybg, WHITEOUT));
                    if (
                        current.primarybg == WHITEOUT 
                    )
                    {
                        vars.DebugOutput("SS / LB2 Boss White Screen detected");
                        split = true;
                    }
                }
                

                if (vars.watchers["chara"].Current == KNUCKLES && zone.Current == SKY_SANCTUARY) //detect final hit on Knux Sky Sanctuary Boss
                {
                    if (vars.watchers["sszboss"].Current == 0 && vars.watchers["sszboss"].Old == 1)
                    {
                        vars.DebugOutput("Knuckles Final Boss 1st phase defeat detected");
                        vars.sszsplit = true;
                    }
                }

            break;
        case "Sonic 3 & Knuckles - Bonus Stages Only":
        case "Sonic & Knuckles - Bonus Stages Only":

            trigger = vars.watchers["trigger"];
            resettrigger = vars.watchers["reset"];
            delactive = vars.watchers["delactive"];
            zone = vars.watchers["zone"];
            act = vars.watchers["act"];
            savefile = vars.watchers["savefile"];
            primarybg = vars.watchers["primarybg"];
            savefilezone = ( vars.isS3 ? vars.watchers["s3savefilezone"] : vars.watchers["savefilezone"] );


            if ( ( vars.watchers["chaosemeralds"].Current + vars.watchers["superemeralds"].Current ) > ( vars.watchers["chaosemeralds"].Old + vars.watchers["superemeralds"].Old ) ) {
                vars.gotEmerald = true;
                vars.emeraldcount = vars.watchers["chaosemeralds"].Current + vars.watchers["superemeralds"].Current;
            }
            if ( primarybg.Changed ) {
                current.primarybg = vars.watchers["primarybg"].Current;
                if ( !vars.isBigEndian ) {
                    current.primarybg = vars.SwapEndiannessLong(primarybg.Current);
                }
            }
            if ( trigger.Changed ) {
                if ( settings["extralogging"] ) {
                    vars.DebugOutput(String.Format("Trigger was: {0} now: {1}", trigger.Old, trigger.Current ) );
                }
                switch ( (int) trigger.Current ) {
                    case 0x00: // Game init - Disable all watchers except trigger.
                        foreach ( var watcher in vars.watchers ) {
                            if ( watcher.Name != "trigger" ) {
                                watcher.Enabled = false;
                                watcher.Reset();
                            }
                        }
                        current.primarybg  = 0;
                        break;
                    case 0x04: // sega logo -> title screen
                        zone.Enabled = true;
                        act.Enabled = true;
                        resettrigger.Enabled = settings["hard_reset"];
                        break;
                    case 0x4C: // data select screen
                        primarybg.Enabled = true;
                        savefile.Enabled = true;
                        savefilezone.Enabled = !vars.isSK;
                        delactive.Enabled = true;
                        break;
                    case 0x8C: // start game
                        vars.watchers["chaosemeralds"].Enabled = true;
                        vars.watchers["superemeralds"].Enabled = true;
                        vars.savefile = savefile.Current;
                        vars.DebugOutput(String.Format("Start game {0} {1} {2:X}", zone.Current, act.Current, trigger.Old) );

                        primarybg.Enabled = false;
                        savefilezone.Enabled = false;
                        savefile.Enabled = false;
                        delactive.Enabled = false;

                        if ( !vars.ingame && act.Current == 0 && 
                            ( 
                                ( zone.Current == 0 && trigger.Old == 0x4C ) ||
                                ( vars.isSK && zone.Current == 7 && trigger.Old == 0x04 )
                            )
                        ) {
                                vars.stopwatch.Start();
                                vars.expectedzone = zone.Current;
                                start = true;
                        }
                        break;
                    case 0x0C: // in level

                        break;
                    case 0x34: // Go to special stage
                        vars.stopwatch.Stop();
                        current.loading = false;
                        break;
                    case 0x48: // Special stage results screen
                        break;

                }
                if ( trigger.Old == 0x48 ) {
                    if ( vars.gotEmerald ) {
                        vars.gotEmerald = false;
                        split = true;
                    } else {
                        vars.timerModel.SkipSplit();
                    }
                    current.loading = true;
                }
            }
            
            // Reset triggers
            if ( 
                // hard reset 
                ( resettrigger.Changed && resettrigger.Current == 0 )
                ||
                // SK zone changed and set to 0.
                ( vars.isSK && zone.Changed && act.Current == 0 && zone.Current == 0 ) ||
                ( 
                    // in Menu
                    trigger.Current == 0x4C 
                    &&
                    (
                        // Delete selected on save screen
                        ( delactive.Changed && delactive.Current == 0xFF )
                        ||
                        // Checking savefile after reset
                        ( 
                            // Before Hydro 1 (0-0 AI1, 0-1 AI2, 1-0 HC1)
                            (vars.expectedact + vars.expectedzone) <= 1 &&
                            // Fading/Faded in
                            current.primarybg == 0xEE0ECC0AAA08 &&
                            // Save file is the same
                            savefile.Current == vars.savefile &&
                            // Savefile zone = AI
                            savefilezone.Current == ANGEL_ISLAND
                        )
                    )
                    
                )
            ) {
                reset = true;
            }


            
            
            break;
        /**********************************************************************************
            ANCHOR START Sonic the Hedgehog (Master System) support
        **********************************************************************************/
        case "Sonic the Hedgehog (Master System)":
            if ( vars.watchers["scorescreen"].Changed ) {
                if ( vars.watchers["scorescreen"].Current == 27 ) {
                    vars.watchers["timebonus"].Enabled = true;
                    vars.triggerTB = true;
                }
                
            }
            if ( vars.ingame ) {
                if ( vars.watchers["input"].Enabled ) {
                    vars.watchers["input"].Enabled = false;
                }
                if ( vars.watchers["menucheck1"].Current == 5 && vars.watchers["menucheck1"].Old <= 1 && vars.watchers["menucheck2"].Current == 4 && vars.watchers["menucheck2"].Old <= 1 ) {
                    reset = true;
                }
                if (
                    (
                        (vars.watchers["level"].Changed && vars.watchers["level"].Current <= 17) || 
                        (vars.watchers["endBoss"].Changed && vars.watchers["endBoss"].Current == 89 && vars.watchers["level"].Current==17)
                    ) 
                    && (vars.watchers["state"].Current != 0 && vars.watchers["level"].Current > 0)
                ) {
                    vars.DebugOutput(String.Format("Split Start of Level {0}", vars.watchers["level"].Current));
                    split = true;
                }
                /*if ( settings["levelselect"] ) {
                    if ( vars.watchers["input"].Old == 207 ) {
                        byte tolevel = vars.watchers["lives"].Current;
                        byte[] tolevelbytes = { 0x00 };
                        switch ( (uint) vars.watchers["input"].Current ) {
                            case 205:
                                tolevel--;
                                break;
                            case 206:
                                tolevel++;
                                break;
                        }
                        tolevelbytes[0] = tolevel;
                        game.WriteBytes( (IntPtr) vars.ringsoffset, tolevelbytes );
                        game.WriteBytes( (IntPtr) vars.leveloffset, tolevelbytes );
                    }
                }*/
            } else if (vars.watchers["state"].Changed && vars.watchers["state"].Old == 128 && vars.watchers["state"].Current == 224 && vars.watchers["level"].Current == 0 && vars.watchers["input"].Current != 255 && vars.watchers["input"].Current > 0) {
                vars.DebugOutput(String.Format("Split Start of Level {0}", vars.watchers["level"].Current));
                start = true;
            } else {
                vars.watchers["input"].Enabled = true;
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

    Func<uint, uint> SwapEndiannessInt = (uint value) => {
        return ((value & 0x000000ff) << 24) +
            ((value & 0x0000ff00) << 8) +
            ((value & 0x00ff0000) >> 8) +
            ((value & 0xff000000) >> 24);
    };

    Func<uint, uint> SwapEndiannessIntAndTruncate = (uint value) => {
        return ((value & 0x00000000) << 24) +
            ((value & 0x0000ff00) << 8) +
            ((value & 0x00ff0000) >> 8) +
            ((value & 0xff000000) >> 24);
    };

    Func<ulong, ulong> SwapEndiannessLong = (ulong value) => {
        return 
            ((value & 0x00000000000000FF) << 56) +
            ((value & 0x000000000000FF00) << 40) +
            ((value & 0x0000000000FF0000) << 24) +
            ((value & 0x00000000FF000000) << 8) +
            ((value & 0x000000FF00000000) >> 8) +
            ((value & 0x0000FF0000000000) >> 24) +
            ((value & 0x00FF000000000000) >> 40) +
            ((value & 0xFF00000000000000) >> 56) 
            ;
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
                target = new SigScanTarget(0, "53 48 83 EC 20 48 8B F1 41 8B F8 0F B7 DA 81 FB 00 C0 00 00 7C 25 48 8B 46 28 8B D3 81 E2 FF 1F 00 00 3B 50 08 0F 83 ?? ?? ?? ??");
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
                    0x0F, 0x83, /* 0x64, 0x01, 0x00, 0x00,         // jae SMS::WriteMemorySega+191 
                    0x48, 0x63, 0xD2                            // movsxd rdx, edx */
                };
                originalCode.InsertRange( 17, BitConverter.GetBytes( (long) scanOffset + 0x27  ) );
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
    vars.SwapEndiannessInt = SwapEndiannessInt;
    vars.SwapEndiannessIntAndTruncate = SwapEndiannessIntAndTruncate;
    vars.SwapEndiannessLong = SwapEndiannessLong;

    refreshRate = 61;

    /* S3K settings */
    settings.Add("s3k", true, "Settings for Sonic 3 & Knuckles");
    settings.Add("actsplit", false, "Split on each Act", "s3k");
    settings.SetToolTip("actsplit", "If unchecked, will only split at the end of each Zone.");
    
    settings.Add("act_mg1", false, "Ignore Marble Garden 1", "actsplit");
    settings.Add("act_ic1", false, "Ignore Ice Cap 1", "actsplit");
    settings.Add("act_lb1", false, "Ignore Launch Base 1", "actsplit");

    settings.Add("pause_bs", false, "Pause for Blue Sphere stages", "s3k");

    settings.Add("hard_reset", true, "Reset timer on Hard Reset?", "s3k");
    
    settings.SetToolTip("act_mg1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");
    settings.SetToolTip("act_ic1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");
    settings.SetToolTip("act_lb1", "If checked, will not split the end of the first Act. Use if you have per act splits generally but not for this zone.");

    settings.SetToolTip("hard_reset", "If checked, a hard reset will reset the timer.");

    /* Sonic Spinball settings */
    settings.Add("ss", true, "Settings for Sonic Spinball (Genesis / Mega Drive)");
    settings.Add("ss_multiball", false, "Split on entry & exit of multiball stages", "ss");
    settings.SetToolTip("ss_multiball", "If checked, will split on entry and exit of extra bonus stages for Max Jackpot Bonus.");

    /* Magical Taruruuto-kun settings */

    settings.Add("mtk", true, "Settings for Magical Taruruuto-kun");
    settings.Add("mtk_before", false, "Split before boss levels", "mtk");
    settings.Add("mtk_after", true, "Split after boss levels", "mtk");

    /* Debug Settings */
    settings.Add("debug", false, "Debugging Options");
    settings.Add("levelselect", false, "Enable Level Select (if supported)", "debug");
    settings.Add("s2smsallemeralds", false, "S2SMS Enable All Emeralds", "debug");
    settings.Add("extralogging", false, "Extra detail for dev/debugging", "debug");

    settings.Add("rtatbinrta", false, "Store RTA-TB in Real-Time (only applies to non-IGT games)");

    Action<string> DebugOutput = (text) => {
        string time = System.DateTime.Now.ToString("dd/MM/yy hh:mm:ss:fff");
        File.AppendAllText(logfile, "[" + time + "]: " + text + "\r\n");
    
        print("[SEGA Master Splitter] "+text);

        
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
    if ( vars.hasRTATB || vars.isSonicCD ) {
        var timebonus = vars.watchers["timebonus"];

        if ( vars.triggerTB ) {
            timebonus.Update(game);
        }
        if ( timebonus.Changed || vars.triggerTB ) {
            
            uint ctb = timebonus.Current;
            

            if ( vars.isSMSS1 ) {
                var tmp = timebonus.Current;
                tmp = vars.SwapEndiannessInt( timebonus.Current );
                if ( vars.isBigEndian ) {
                    tmp = vars.SwapEndiannessIntAndTruncate( timebonus.Current );
                }
                ctb  = (uint) ( Int32.Parse(String.Format("{0:X8}", tmp)) / 10 );
                vars.DebugOutput(String.Format("TB {0:X8}, {1} {1:X8}", tmp,ctb));
                vars.triggerTB = false;
            } else if ( vars.isBigEndian ) {
                ctb  = vars.SwapEndianness(timebonus.Current);
            }

            current.timebonus = ctb;
            if ( current.timebonus > old.timebonus ) {
                // 5000 = 50000K TB
                vars.timebonusms = ( current.timebonus /599.228 ) * 1000;
                if ( vars.isGenSonic1or2 && !vars.isGenSonic1 && current.timebonus > 999 ) {
                    // add 2s for continues on S2
                    vars.timebonusms += 2000;
                }

            } else if ( current.timebonus < old.timebonus && vars.timebonusms > 0 ) {
                vars.timebonusms = Math.Round(vars.timebonusms );
                vars.DebugOutput(String.Format(  "attempting to pause for: {0} ms", vars.timebonusms));
                vars.stopwatch.Start();
                timebonus.Enabled = false;
            }
        }
        if ( vars.stopwatch.IsRunning ) {
            var currentElapsedTime = vars.stopwatch.ElapsedMilliseconds; 
            if ( currentElapsedTime < ( vars.timebonusms - 31 ) ) {
                current.loading = true;
            } else {
                int sleeptime = (int) (vars.timebonusms - currentElapsedTime);
                if ( sleeptime > 0 ) {
                    Thread.Sleep( sleeptime );
                }
                
                vars.DebugOutput(String.Format("Paused for: {0} ms, was meant to stop for {1}, ajusted from {2}", vars.stopwatch.ElapsedMilliseconds, vars.timebonusms, currentElapsedTime));
                vars.stopwatch.Reset();
                timebonus.Current = 0;
                timebonus.Old = 0;
                current.timebonus = 0;
                current.loading = false;

            }
        }
    }

    if ( settings["rtatbinrta"] && current.loading != old.loading ) {
        vars.timerModel.Pause(); // Pause/UnPause
    } 
    return current.loading;
}

gameTime
{
    if ( vars.juststarted ) {
        vars.juststarted = false;
        return TimeSpan.FromMilliseconds(0);
    }

    if ( vars.isS3K && vars.addspecialstagetime && !current.split ) { 
        vars.addspecialstagetime = false; 
        var currentElapsedTime = vars.specialstagetimer.ElapsedMilliseconds; 
        vars.specialstagetimer.Reset(); 
        vars.specialstagetimeadded = true; 
        current.split = true;
        return TimeSpan.FromMilliseconds(timer.CurrentTime.GameTime.Value.TotalMilliseconds + currentElapsedTime);
    } 
    if ( !vars.isIGT ) {
        return TimeSpan.FromMilliseconds(timer.CurrentTime.GameTime.Value.TotalMilliseconds);
    }
    if(((IDictionary<String, object>)current).ContainsKey("gametime")) {
        return current.gametime;
    }
}
