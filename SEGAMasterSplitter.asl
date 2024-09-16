/*
    * SEGA Master Splitter
    Splitter designed to handle multiple 8 and 16 bit SEGA games running on various emulators
*/

state("retroarch") {}
state("Fusion") {}
state("gens") {}
state("SEGAGameRoom") {}
state("SEGAGenesisClassics") {}
state("blastem") {}
state("Sonic3AIR") {}

init
{
    vars.gamename = timer.Run.GameName;
    vars.livesplitGameName = vars.gamename;

    
    ulong memoryOffset = 0, smsMemoryOffset = 0;
    ulong baseAddress;
    IntPtr codeOffset;

    ulong refLocation = 0, smsOffset = 0;
    baseAddress = (ulong) modules.First().BaseAddress;
    bool isBigEndian = false, isFusion = false, isAir = false;
    SigScanTarget target;

    switch ( game.ProcessName.ToLower() ) {
        case "retroarch":
            ProcessModuleWow64Safe libretromodule = modules.Where(m => m.ModuleName == "genesis_plus_gx_libretro.dll" || m.ModuleName == "blastem_libretro.dll").First();
            baseAddress = (ulong) libretromodule.BaseAddress;
            if ( libretromodule.ModuleName == "genesis_plus_gx_libretro.dll" ) {
                vars.DebugOutput("Retroarch - GPGX");
                if ( game.Is64Bit() ) {
                    target = new SigScanTarget(0x10, "85 C9 74 ?? 83 F9 02 B8 00 00 00 00 48 0F 44 05 ?? ?? ?? ?? C3");
                    codeOffset = vars.LookUpInDLL( game, libretromodule, target );
                    if ( codeOffset == IntPtr.Zero ) {
                        target = new SigScanTarget(0x0D, "85 C9 74 ?? 31 C0 83 F9 02 48 0F 44 05 ?? ?? ?? ?? C3");
                        codeOffset = vars.LookUpInDLL( game, libretromodule, target );
                    }
                    
                    codeOffset = vars.LookUpInDLL( game, libretromodule, target );
                    ulong memoryReference = (ulong) memory.ReadValue<int>( codeOffset );
                    refLocation = ( (ulong) codeOffset + 0x04 + memoryReference );
                } else {
                    target = new SigScanTarget(0, "8B 44 24 04 85 C0 74 18 83 F8 02 BA 00 00 00 00 B8 ?? ?? ?? ?? 0F 45 C2 C3 8D B4 26 00 00 00 00");
                    codeOffset = vars.LookUpInDLL( game, libretromodule, target );
                    refLocation = (ulong) codeOffset + 0x11;
                }
            } else if ( libretromodule.ModuleName == "blastem_libretro.dll" ) {
                vars.DebugOutput("Retroarch - BlastEm!");
                goto case "blastem";
            }
            
            break;

        case "blastem":
            target = new SigScanTarget(0, "81 F9 00 00 E0 00 72 10 81 E1 FF FF 00 00 83 F1 01 8A 89 ?? ?? ?? ?? C3");
            codeOffset = vars.LookUp( game, target );
            refLocation = (ulong) codeOffset + 0x13;

            target = new SigScanTarget(0, "66 41 81 FD FC FF 73 12 66 41 81 E5 FF 1F 45 0F B7 ED 45 8A AD ?? ?? ?? ?? C3");
            codeOffset = vars.LookUp( game, target );
            smsOffset = (ulong) codeOffset + 0x15;

            if ( refLocation == 0x13 && smsOffset == 0x15 ) {
                throw new NullReferenceException (String.Format("Memory offset not yet found. Base Address: 0x{0:X}", (long) baseAddress ));
            }
            break;
        case "gens":
            refLocation = (ulong) memory.ReadValue<int>( IntPtr.Add( (IntPtr) baseAddress, 0x40F5C ) );
            break;
        case "fusion":
            refLocation = (ulong) IntPtr.Add((IntPtr) baseAddress, 0x2A52D4);
            smsOffset = (ulong) IntPtr.Add((IntPtr) baseAddress, 0x2A52D8 );
            isBigEndian = true;
            isFusion = true;
            break;
        case "segagameroom":
            baseAddress = (ulong) modules.Where(m => m.ModuleName == "GenesisEmuWrapper.dll").First().BaseAddress;
            refLocation = (ulong) IntPtr.Add((IntPtr) baseAddress, 0xB677E8);
            break;
        case "segagenesisclassics":
            refLocation = (ulong) IntPtr.Add((IntPtr) baseAddress, 0x71704);
            break;
        case "sonic3air":
            isAir = true;

            foreach (var page in game.MemoryPages()) {
                if ((int)page.RegionSize == 0x521000) {
                    refLocation = (ulong) page.BaseAddress + 0x3FFF00 + 0x120;
                    break;
                }
            }
            if ( refLocation > 0 ) {
                ulong injectionMem = (ulong) game.AllocateMemory(0x08);
                game.Suspend();
                game.WriteBytes(new IntPtr((long)injectionMem), BitConverter.GetBytes( (long) refLocation ) );
                game.Resume();
                refLocation = injectionMem;
            }
            isBigEndian = true;
            break;
    }

    vars.DebugOutput(String.Format("refLocation: 0x{0:X}", refLocation));
    if ( refLocation > 0 ) {
        if ( game.Is64Bit() ) {
            memoryOffset = memory.ReadValue<ulong>( (IntPtr) refLocation );
        } else {
            memoryOffset = memory.ReadValue<uint>( (IntPtr) refLocation );
        }
        if ( memoryOffset == 0 ) {
            memoryOffset = refLocation;
        }
    }
    if ( smsOffset == 0 ) {
        smsOffset = refLocation;
    }
    if ( game.Is64Bit() ) {
        vars.emuoffsets = new MemoryWatcherList
        {
            new MemoryWatcher<ulong>( (IntPtr) refLocation ) { Name = "genesis", FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull },
            new MemoryWatcher<ulong>( (IntPtr) smsOffset   ) { Name = "sms", FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull },
            new MemoryWatcher<ulong>( (IntPtr) baseAddress ) { Name = "baseaddress", FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull }
        };
    } else {
        vars.emuoffsets = new MemoryWatcherList
        {
            new MemoryWatcher<uint>( (IntPtr) refLocation ) { Name = "genesis", FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull },
            new MemoryWatcher<uint>( (IntPtr) smsOffset   ) { Name = "sms", FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull },
            new MemoryWatcher<uint>( (IntPtr) baseAddress ) { Name = "baseaddress", FailAction = MemoryWatcher.ReadFailAction.SetZeroOrNull }
        };
    }
    if ( memoryOffset == 0 && smsOffset == 0 ) {
        Thread.Sleep(500);
        throw new NullReferenceException (String.Format("Memory offset not yet found. Base Address: 0x{0:X}", (long) baseAddress ));
    }

    vars.isBigEndian = isBigEndian;


    vars.addByteAddresses = (Action <Dictionary<string, long>>)(( addresses ) => {
        foreach ( var byteaddress in addresses ) {
            vars.watchers.Add( new MemoryWatcher<byte>( 
                (IntPtr) ( ( vars.isSMS ? smsMemoryOffset : memoryOffset ) + (ulong) byteaddress.Value ) 
                ) { Name = byteaddress.Key, Enabled = true } 
            );
        }
    });
    vars.addUShortAddresses = (Action <Dictionary<string, long>>)(( addresses ) => {
        foreach ( var ushortaddress in addresses ) {
            vars.watchers.Add( new MemoryWatcher<ushort>( 
                (IntPtr) ( ( vars.isSMS ? smsMemoryOffset : memoryOffset ) + (ulong) ushortaddress.Value )
                ) { Name = ushortaddress.Key, Enabled = true } 
            );
        }
    });
    vars.addUIntAddresses = (Action <Dictionary<string, long>>)(( addresses ) => {
        foreach ( var uintaddress in addresses ) {
            vars.watchers.Add( new MemoryWatcher<uint>( 
                (IntPtr) ( ( vars.isSMS ? smsMemoryOffset : memoryOffset ) + (ulong) uintaddress.Value )
                ) { Name = uintaddress.Key, Enabled = true } 
            );
        }
    });
    vars.addULongAddresses = (Action <Dictionary<string, long>>)(( addresses ) => {
        foreach ( var ushortaddress in addresses ) {
            vars.watchers.Add( new MemoryWatcher<ulong>( 
                (IntPtr) ( ( vars.isSMS ? smsMemoryOffset : memoryOffset ) + (ulong) ushortaddress.Value )
                ) { Name = ushortaddress.Key, Enabled = true } 
            );
        }
    });
    
    vars.activateLevelSelect = (Func <bool>)(() => {
        var levelselect = vars.watchers["levelselect"];
        if ( levelselect.Enabled == false ) {
            levelselect.Enabled = true;
        }
        if ( vars.isSMSGGSonic2 ) {
            if ( vars.watchers["systemflag"].Current == 1 ) {
                vars.levelselectbytes = new byte[] { 0xB6 };
            }
            if ( settings["s2smsallemeralds"] ) {
                // enable all emeralds
                IntPtr emeraldcountoffset = (IntPtr) smsMemoryOffset + vars.emeraldcountoffset;
                IntPtr emeraldflagsoffset = (IntPtr) smsMemoryOffset + vars.emeraldflagsoffset;
                if ( vars.watchers["emeraldcount"].Current < vars.watchers["zone"].Current ) {
                    vars.DebugOutput("Updating Emerald Count");
                    game.WriteBytes( (IntPtr) emeraldcountoffset, new byte[] { vars.watchers["zone"].Current } );
                }
                if ( vars.watchers["zone"].Current == 5 && vars.watchers["emeraldflags"].Current < 0x1F ) {
                    vars.DebugOutput("Updating Emerald Flags");
                    game.WriteBytes( (IntPtr) emeraldflagsoffset, new byte[] { 0x1F } );
                }
                if ( vars.watchers["zone"].Current == 6 && vars.watchers["emeraldflags"].Current < 0x3F ) {
                    vars.DebugOutput("Updating Emerald Flags");
                    game.WriteBytes( (IntPtr) emeraldflagsoffset, new byte[] { 0x3F } );
                }
            }
        }
        IntPtr lsoffset = (IntPtr ) ( vars.isSMS ? smsMemoryOffset : memoryOffset ) + vars.levelselectoffset;
        if ( (long) vars.levelselectoffset > 0 && levelselect.Current != vars.levelselectbytes[0] ) {
            vars.DebugOutput(String.Format("Enabling Level Select at {0:X8} with {1} because it was {2}", lsoffset,  vars.levelselectbytes[0], levelselect.Current));
            
            game.WriteBytes( lsoffset , (byte[]) vars.levelselectbytes );
            return true;
        }
        return false;
    });

    vars.reInitialise = (Action)(() => {
        vars.isSMS = false;
        vars.emuoffsets.UpdateAll(game);
        memoryOffset = vars.emuoffsets["genesis"].Current;
        if ( memoryOffset == 0 && refLocation > 0 ) {
            memoryOffset = refLocation;
        }
        smsMemoryOffset = vars.emuoffsets["sms"].Current;


        if ( isFusion ) {
            smsMemoryOffset = vars.emuoffsets["sms"].Current + (int) 0xC000;
        }

        vars.DebugOutput(String.Format("memory should start at {0:X}", memoryOffset));
        vars.DebugOutput(String.Format("SMS memory should start at {0:X}", smsMemoryOffset));

        vars.isIGT = false;
        current.loading = false;
        vars.igttotal = 0;

        vars.ingame = false;
        vars.watchers = new MemoryWatcherList {};
        vars.levelselectoffset = 0;
        vars.isGenSonic1 = false;
        vars.isGenSonic1or2 = false;
        vars.isSK = false;
        vars.isS3 = false;
        vars.isSMSS1 = false;
        vars.isSMSGGSonic2 = false;
        vars.hasRTATB = false;
        vars.isAir = isAir;
        vars.isSonicChaos = false;
        vars.isSonicCD = false;
        vars.nextsplit = "";
        vars.startTrigger = 0x8C;
        vars.splitInXFrames = -1;
        vars.bossdown = false;
        vars.juststarted = false;
        vars.triggerTB = false;
        vars.addspecialstagetime = false; 
        vars.specialtriggercounter = 0;
        vars.levelselectbytes = new byte[] {0x01}; // Default as most are 0 - off, 1 - on
        IDictionary<string, string> expectednextlevel = new Dictionary<string, string>();
        vars.expectednextlevel = expectednextlevel;
        vars.expectedzonemap = false;
        vars.stopwatch = new Stopwatch();
        vars.timebonusms = 0;
        vars.livesplitGameName = vars.gamename;
        switch ( (string) vars.gamename ) {
            // games migrated to memory addresses being within their blocks
            case "Alex Kidd in Miracle World":
            case "Earthworm Jim":
            case "Cool Spot (Genesis)":
            case "Dr. Robotnik's Mean Bean Machine":
            case "Sonic 3D Blast":
            case "Sonic Eraser":
            case "Tiny Toon Adventures: Buster's Hidden Treasure":
            case "Magical Taruruuto-kun":
            case "Mystic Defender":
            case "Sonic CD":
            case "Sonic Triple Trouble":
            case "Cyber Shinobi":
                break;
            // S1SMS aliases
            case "Sonic the Hedgehog (Master System)":
            case "Sonic the Hedgehog (SMS)":
                vars.gamename = "Sonic the Hedgehog (Master System)";
                break;
            // Chaos aliases
            case "Sonic Chaos":
            case "Sonic Chaos (Master System)":
            case "Sonic Chaos (Game Gear)":
                vars.gamename = "Sonic Chaos";
                break;
            // Spinball aliases
            case "Sonic Spinball":
            case "Sonic Spinball (Genesis / Mega Drive)":
                vars.gamename = "Sonic Spinball (Genesis / Mega Drive)";
                break;
            // S2 8 bit aliases
            case "Sonic the Hedgehog 2 (Game Gear / Master System)":
            case "Sonic the Hedgehog 2 (Master System)":
            case "Sonic the Hedgehog 2 (SMS)":
            case "Sonic the Hedgehog 2 (GG)":
            case "Sonic the Hedgehog 2 (Game Gear)":
            case "Sonic 2 Rebirth":
                vars.gamename = "Sonic the Hedgehog 2 (Game Gear / Master System)";
                break;
            /**********************************************************************************
                ANCHOR START Sonic the HedgeHog 1 & 2 Genesis watchlist
            **********************************************************************************/
            case "Sonic the Hedgehog (Genesis / Mega Drive)":
            case "Knuckles the Echidna in Sonic the Hedgehog":
            case "Sonic the Hedgehog":
            case "Sonic 1":
            case "Sonic 1 (Genesis)":
            case "Sonic 1 (Mega Drive)":
                vars.gamename = "Sonic the Hedgehog (Genesis / Mega Drive)";
                break;
            case "Sonic the Hedgehog 2 (Genesis / Mega Drive)":
            case "Sonic the Hedgehog 2":
            case "Sonic 2":
            case "Sonic 2 (Genesis)":
            case "Sonic 2 (Mega Drive)":
                vars.gamename = "Sonic the Hedgehog 2 (Genesis / Mega Drive)";
                break;
            /**********************************************************************************
                ANCHOR START Sonic the Hedgehog 3 & Knuckles watchlist
            **********************************************************************************/
            case "Sonic the Hedgehog 3":
            case "Sonic 3":
                vars.isS3 = true;
                vars.levelselectoffset = isBigEndian ? 0xFFD0 : 0xFFD1;
                goto case "Sonic 3 & Knuckles";
            case "Sonic & Knuckles":
            case "Sonic and Knuckles":
                vars.isSK = true;
                goto case "Sonic 3 & Knuckles";
            case "Sonic & Knuckles - Bonus Stages Only":
                vars.isSK = true;
                goto case "Sonic 3 & Knuckles - Bonus Stages Only";
            case "Sonic 3 & Knuckles - Bonus Stages Only":
                current.loading = true;
                vars.gamename = "Sonic 3 & Knuckles - Bonus Stages Only";
                goto case "GenericS3K";
            case "Sonic 3 & Knuckles":
            case "Sonic 3 and Knuckles":
            case "Sonic 3 Complete":
            case "Sonic 3: Angel Island Revisited":
            case "S3AIR - D.A. Garden Edition":
                vars.gamename = "Sonic 3 & Knuckles";
                goto case "GenericS3K";
            case "GenericS3K":
                if ( !vars.isS3 ) {
                    vars.levelselectoffset =  isBigEndian ? 0xFFE0 : 0xFFE1;
                }
                current.primarybg  = 0;
                vars.expectedzone = 0;
                vars.expectedact = 1;
                vars.sszsplit = false; //boss is defeated twice
                vars.savefile = 255;
                vars.skipsAct1Split = false;
                vars.specialstagetimer = new Stopwatch(); 
                
                vars.specialstagetimeadded = false; 
                vars.gotEmerald = false;
                vars.chaoscatchall = false;
                vars.chaossplits = 0;
                vars.hasRTATB = true;
                break;
            default:
                throw new NullReferenceException (String.Format("Game {0} not supported.", vars.gamename ));
        
            
        }
        vars.DebugOutput("Game from LiveSplit found: " + vars.gamename);
    });

    vars.reInitialise();
}

update
{
    var start = false;
    var split = false;
    var reset = false;
    string currentlevel = "";
    bool isBigEndian = vars.isBigEndian;
    var gametime = TimeSpan.FromDays(999);
    var oldgametime = gametime;
    bool lschanged = false;
    const ulong WHITEOUT = 0x0EEE0EEE0EEE0EEE;


    uint changed = 0;
    uint watchercount = 0;
    string changednames = "";
    bool hasLevelSelect = false;
    //vars.watchers.UpdateAll(game);
    bool runJustStarted = !vars.ingame && timer.CurrentPhase == TimerPhase.Running;
    
    if ( runJustStarted ) {
        //pressed start run or autostarted run
        vars.DebugOutput("run start detected");
        vars.igttotal = 0;
        vars.ms = 0;
        vars.ingame = true;
        current.timebonus = 0;
        current.scoretally = 0;
        if ( vars.isGenSonic1or2 ) {
            //current.loading = true;
            current.hascontinue = false;
        }
        if ( vars.isSonicCD ) {
            current.totalseconds = 0;
            vars.wait = false;
        }
        
    } else if ( vars.ingame && !( timer.CurrentPhase == TimerPhase.Running || timer.CurrentPhase == TimerPhase.Paused ) ) {
        vars.DebugOutput("run stop detected");
        current.loading = false;
        old.loading = false;
        vars.ingame = false;
        vars.stopwatch.Reset();
        return false;
    }
    foreach ( var watcher in vars.watchers ) {
        watchercount++;
        bool watcherchanged = watcher.Update(game);
        
        if ( watcherchanged ) {
            changed++;
            if ( settings["extralogging"] ) {
                changednames = changednames + watcher.Name + " ";
            }
        }
        if ( watcher.Name == "levelselect" ) {
            hasLevelSelect = true;
        }
    }
    if ( watchercount == 0 ) {
        current.start = false;
        current.split = false;
        current.reset = false;
    } else {
        if ( settings["levelselect"] && hasLevelSelect ) {
            lschanged = vars.activateLevelSelect();
        }
        if ( vars.splitInXFrames == 0 ) {
            vars.splitInXFrames = -1;
            split = true;
        } else if ( vars.splitInXFrames > 0 ) {
            vars.splitInXFrames--;
        }
        if ( changed == 0 && !runJustStarted ) {
            vars.emuoffsets.UpdateAll(game);
            if ( vars.livesplitGameName != timer.Run.GameName || vars.emuoffsets["genesis"].Old != vars.emuoffsets["genesis"].Current || vars.emuoffsets["baseaddress"].Current != vars.emuoffsets["baseaddress"].Old || vars.emuoffsets["sms"].Current != vars.emuoffsets["sms"].Old ) {
                vars.DebugOutput("Game in Livesplit changed or memory address changed, reinitialising...");
                vars.gamename = timer.Run.GameName;
                vars.reInitialise();
            }
            return vars.stopwatch.IsRunning || lschanged || vars.juststarted || split;
        }
        if ( settings["extralogging"] ) {
            vars.DebugOutput(String.Format( "{0} things changed: " + changednames, changed ) );
        }

    }

    switch ( (string) vars.gamename ) {
        /**********************************************************************************
            ANCHOR START Alex Kidd in Miracle World Support
        **********************************************************************************/
        case "Alex Kidd in Miracle World":
            if ( watchercount == 0 ) {
                vars.isSMS = true;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level", 0x0023  },
                    { "trigger", 0x03C1 },
                    { "lives", 0x0025 },
                    { "complete", 0x1800 }
                });
                return false;
            }
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
            ANCHOR START Earthworm Jim Support
        **********************************************************************************/
        case "Earthworm Jim":
            if ( watchercount == 0 ) {
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level", isBigEndian ? 0xA692 : 0xA693 },
                    /*
                        00: New Junk City
                        01: What the heck?
                        02: Snowman
                        03: Evil the Cat
                        04-06: Snot the problem 1-3
                        07: For Pete's sake!
                        08: Buttville pt.2
                        09: Buttville pt.1 (helicopter)
                        10: Level 5 pt.1 & pt.3
                        11: Level 5 pt.4 (chicken fly / boss phase 2)
                        12: Level 5 pt.2 (naked worm section)
                        13: Intestinal distress
                        14: Down the tubes pt.1
                        15: Down the tubes pt.2 (Tube race)
                        16-22: Andy asteroids 1-7
                        23-27: Who turned out the lights? 1-5 (Level 5 bonus section)
                        28: Psycrow fight
                    */
                    { "jim_control", isBigEndian ? 0xFD23 : 0xFD22 },   //255 when no control over Jim, 00 otherwise
                    { "jim_action", isBigEndian ? 0xFDEA : 0xFDEB },    //61 when jim disappears after defeating the Queen
                    { "demo", isBigEndian ? 0xFF98 : 0xFF99 },          //01 when demo mode, 00 otherwise
                    { "game_started", isBigEndian ? 0xFBD7 : 0xFBD6 }   //170->202->208->214->220
                });

                vars.addUShortAddresses(new Dictionary<string, long>() {
                    { "groovy_1", 0xFCBC },
                    { "groovy_2", 0xFCBE },
                    { "menu_screen", 0x9928 } 
                    /*
                        82CC: SEGA logo
                        8862: Main Menu
                        8842: U're the best
                        750C: Black screen (transition)
                        8902: Groovy (sadly cannot be used for splitting due to occasional false-negatives while mashing buttons)
                        8982: Level title
                        7BAC: Jim's death screen
                        8A02: Hey, Shiny Crew & D. L. Only! (Cheat Menu logo)
                        760C: Cheat Menu itself   
                    */
                });
                return false;
            }    

            current.menuScreen = vars.watchers["menu_screen"].Current;
            if ( vars.isBigEndian ) {
                current.menuScreen = vars.SwapEndianness(current.menuScreen);
            }

            if ( !vars.ingame ) {
                if ( current.menuScreen == 0x8862 && vars.watchers["demo"].Current == 0 && vars.watchers["game_started"].Current == 220 ) {
                    start = true;
                }
            } else {
                if ( (settings["ewj1_reset_sega_logo"] && current.menuScreen == 0x82CC)
                    || (settings["ewj1_reset_cheat_menu"] && current.menuScreen == 0x8A02) ) {

                    reset = true;

                } else if (current.menuScreen != 0x760C) {      //disable split checks while being in the cheat menu

                    //most of the splits should be performed at the "Groovy" screen after a level

                    current.groovy1 = vars.watchers["groovy_1"].Current;
                    current.groovy2 = vars.watchers["groovy_2"].Current;
                    if ( vars.isBigEndian ) {
                        current.groovy1 = vars.SwapEndianness(current.groovy1);
                        current.groovy2 = vars.SwapEndianness(current.groovy2);
                    }

                    current.level = vars.watchers["level"].Current;

                    if (current.groovy1 == 231 && current.groovy2 == 315 && current.groovy1 != old.groovy1 && current.groovy2 != old.groovy2) {
                        
                        switch ( (byte) current.level ) {
                            case 0: case 3: case 6: case 7: case 11: case 13: case 14: case 15:
                                //regular splits
                                split = true;                  
                                break;
                            case 16: case 17: case 18: case 19: case 20: case 21: case 22:
                                //splits after Andy Asteroids levels (excluding Psycrow ending)
                                if (settings["ewj1_split_andy"]) {
                                    split = true;             
                                }
                                break;
                        }
                    }

                    //below are the splits when the "Groovy" screen doesn't appear or simply isn't appropriate for splitting
                    
                    if (current.level == 8 && vars.watchers["jim_action"].Current == 61 
                        && vars.watchers["jim_control"].Current == 255 && vars.watchers["jim_control"].Old != 255) {
                        //final split after defeating the Queen
                        split = true;
                    }
                    if (settings["ewj1_split_andy"] && old.level == 28 && current.level != 28) {
                        //split after winning the fight with Psycrow in case of failed Andy asteroids race
                        split = true;
                    }
                    if (settings["ewj1_split_evil_cat"] && old.level == 1 && current.level == 3) {
                        //optional split before the boss fight in What the Heck?
                        split = true;
                    }
                    if (settings["ewj1_split_chicken"] && old.level == 10 && current.level == 11) {
                        //optional split before the 2nd boss fight in Level 5 ("Chicken fly" section)
                        split = true;
                    }
                    if (settings["ewj1_split_helicopter"] && old.level == 9 && current.level == 8) {
                        //optional split between the "helicopter" and the main parts in Buttville
                        split = true;
                    }
                    if (settings["ewj1_split_snots"] && (old.level == 4 && current.level == 5 || old.level == 5 && current.level == 6)) {
                        //optional split after every fight in Snot a problem levels (by default is splits only after the 3rd round)
                        split = true;
                    }
                }
            }
            break;
        /**********************************************************************************
            ANCHOR START Cool Spot Support
        **********************************************************************************/
        case "Cool Spot (Genesis)":
            if ( watchercount == 0 ) {
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level_id", isBigEndian ? 0x0710 :  0x0711 },
                    { "cage_open", isBigEndian ? 0xF578 : 0xF579  },
                    { "game_started", isBigEndian ? 0x083D : 0x083E },
                    { "reset_indicator", isBigEndian ? 0xF4D5 : 0xF4D6 }
                });

                return false;
            }
            if ( !vars.ingame ) {
                if ( vars.watchers["level_id"].Current == 3 && vars.watchers["game_started"].Current != 0 && vars.watchers["game_started"].Old == 0 ) {
                    start = true;
                }
            } else {
                bool splitOnCageHit = settings["coolspot_split_on_cage_hit"];

                if ( ( splitOnCageHit && vars.watchers["cage_open"].Current == 255 && vars.watchers["cage_open"].Old != 255 )
                        || ( !splitOnCageHit && vars.watchers["level_id"].Current != vars.watchers["level_id"].Old ) ) {
                    split = true;
                }

                if ( vars.watchers["reset_indicator"].Current == 0 && vars.watchers["reset_indicator"].Old != 0 ) {
                    reset = true;
                }
            }
            break;
        /**********************************************************************************
            ANCHOR START Cyber Shinobi
        **********************************************************************************/
        case "Cyber Shinobi":
            if ( watchercount == 0 ) {
                vars.isSMS = true;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level", 0x000C  },
                    { "trigger", 0x0002 },
                    { "lives", 0x000E },
                });
                return false;
            }
            // Convert next split to int
            int nextSplit;
            var success = int.TryParse(vars.nextsplit, out nextSplit);
            nextSplit = success ? nextSplit : 0;
            if ( vars.watchers["trigger"].Current == 1) {
                reset = true;
                break;
            }
            if ( !vars.ingame) {
                if (vars.watchers["level"].Current == 0 && vars.watchers["trigger"].Current == 17 && vars.watchers["lives"].Current == 5) {
                    start = true;
                    vars.nextsplit = "2";
                }
                break;
            }
            // we are ingame here
            var isBlackScreenOfNextLevel = vars.watchers["level"].Current == nextSplit - 1  && vars.watchers["trigger"].Current == 17;
            var isBlackScreenAfterBrainDead = vars.watchers["level"].Current == 5  && vars.watchers["trigger"].Current == 19;
            if ( isBlackScreenOfNextLevel || isBlackScreenAfterBrainDead) {
                vars.nextsplit = "" + (nextSplit + 1);
                // Have control so start timer
                split = true;
            }
            break;
        /**********************************************************************************
            ANCHOR START Dr. Robotnik's Mean Bean Machine Support
        **********************************************************************************/
        case "Dr. Robotnik's Mean Bean Machine":
            if ( watchercount == 0 ) {
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "gamestate", isBigEndian ? 0x0113 :  0x0113 },
                    { "gameover", isBigEndian ? 0x0A3A  : 0x0A3B },
                    { "defeated", isBigEndian ? 0x19AA : 0x19AA  }
                });

                return false;
            }
            if ( !vars.ingame ) {
                
                if ( vars.watchers["gamestate"].Current == 3 && vars.watchers["gamestate"].Old != 1 ) {
                    start = true;
                }
            } else {
                
                if ( vars.watchers["gameover"].Current == 0 && vars.watchers["defeated"].Current == 255 && vars.watchers["defeated"].Old != 255 ) {
                    split = true;
                }
                if ( vars.watchers["gamestate"].Current == 0 && vars.watchers["gamestate"].Old > 0 ) {
                    reset = true;
                }
            }
            break;
        /**********************************************************************************
            ANCHOR START Magical Taruruuto-kun Support
        **********************************************************************************/
        case "Magical Taruruuto-kun":
            if ( watchercount == 0 ) {
                vars.levelselectbytes = new byte[] {0xC0};
                vars.levelselectoffset =  isBigEndian ? 0xFD31 : 0xFD30 ;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level",        isBigEndian ? 0xFD4B : 0xFD4A },
                    { "gamemode",     isBigEndian ? 0xFEF9 : 0xFEF8 },
                    { "menu",         isBigEndian ? 0xF806 : 0xF807 },
                    { "clearelement", isBigEndian ? 0xF973 : 0xF973 },
                    { "levelselect",  vars.levelselectoffset }
                });
                return false;
            }
            MemoryWatcher<byte> mtkgamemode     = vars.watchers["gamemode"],        mtklevel = vars.watchers["level"],
                                mtkclearelement = vars.watchers["clearelement"],    mtkmenu = vars.watchers["menu"];

            if ( !vars.ingame && mtkgamemode.Old == 1 && mtkgamemode.Current == 1 && mtklevel.Current == 1) {
                start = true;
            }

            if ( vars.ingame ) {
                if ( mtklevel.Current == 67 && mtkclearelement.Current == 2 ) {
                    split = true;
                }
                if ( mtklevel.Current > mtklevel.Old ) {
                    /*
                        Stages:
                        6 Jabao (footballer boss) Stage 1 boss
                        15 Mikotaku (boss)
                        19 Mimora (boss) Stage 2 boss
                        22 vamp boss?
                        31 Dowahha (boss) Stage 3 boss
                        33 Return of Harakko (autoscroller boss)
                        67 Rivar

                    */
                    if ( settings["mtk_before"] ) {
                        switch ( (int) mtklevel.Current ) {
                            case 6: case 15: case 19: case 22: case 31: case 33: case 67:
                                split = true;
                                break;
                        }
                    }
                    if ( settings["mtk_after"] ) {
                        switch ( (int) mtklevel.Old ) {
                            case 6: case 15: case 19: case 22: case 31: case 33:
                                split = true;
                                break;
                        }
                    }
                }

                if ( mtkgamemode.Current == 0 && mtkmenu.Old == 0 && mtkmenu.Current == 1) {
                    reset = true;
                }
            }

            break;
        /**********************************************************************************
            ANCHOR START Mystic Defender Support
        **********************************************************************************/
        case "Mystic Defender":
            if ( watchercount == 0 ) {

                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "stage",  isBigEndian ? 0xF627 : 0xF627 },
                    { "level",  isBigEndian ? 0xF629 : 0xF628 },
                    { "bosshp", isBigEndian ? 0xE61F : 0xE61E }

                });
                vars.addUShortAddresses(new Dictionary<string, long>() {
                    { "menucheck", 0xD010 }
                });
                return false;
            }
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
            if ( watchercount == 0 ) {
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "menuoption",         ( vars.isBigEndian ? 0xF92F : 0xF92E ) },
                    { "inmenu",             ( vars.isBigEndian ? 0xF90C : 0xF90D ) },
                    { "trigger",            ( vars.isBigEndian ? 0xF907 : 0xF906 ) },
                    { "level",              ( vars.isBigEndian ? 0xF973 : 0xF973 ) },
                    { "roundcleartrigger",  ( vars.isBigEndian ? 0xF01E : 0xF01F ) },
                    { "bosskill",           ( vars.isBigEndian ? 0xF8FF : 0xF8FE ) }
                });
                vars.addUShortAddresses(new Dictionary<string, long>() {
                    { "roundclear", ( vars.isBigEndian ? 0xB7C0 : 0xB7C0 ) }
                });
                vars.watchers["level"].Enabled = false;
                vars.watchers["roundclear"].Enabled = false;
                return false;
            }
            
            if ( vars.watchers["inmenu"].Current == 0 && vars.watchers["inmenu"].Old == 1 && vars.watchers["menuoption"].Current == 0 && vars.watchers["trigger"].Old == 5 && vars.watchers["trigger"].Current == 6 ) {
                vars.watchers["roundclear"].Enabled  = false;
                start = true;

            }
            if ( vars.watchers["trigger"].Current == 5 &&  vars.watchers["trigger"].Old < 5 ) {
                reset = true;
            }
            
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
            if ( watchercount == 0 ) {
                vars.levelselectoffset = 0x040D;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level",          isBigEndian ? 0x067F : 0x067E },
                    { "ingame",         0xF749 },
                    { "ppboss",         isBigEndian ? 0xD189 : 0xD188 },
                    { "ffboss",         isBigEndian ? 0x0BA9 : 0x0BA8 },
                    { "emeralds",       isBigEndian ? 0x06A3 : 0x06A2 },
                    { "fadeout",        isBigEndian ? 0x0A1B : 0x0A1A },
                    { "levelselect",    vars.levelselectoffset }
                    
                });
                vars.addUShortAddresses(new Dictionary<string, long>() {
                    { "levelframecount", 0x0A5C }
                });
                vars.igttotal = 0;
                vars.isIGT = true;
                current.igt = 0;
                return false;
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
            if ( watchercount == 0 ) {
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level", vars.isBigEndian ? 0xC711 : 0xC710  },
                    { "start", vars.isBigEndian ? 0xBE23 : 0xBE24 },
                });
                return false;
            }
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
            if ( watchercount == 0 ) {
                vars.levelselectoffset = isBigEndian ? 0xF8F8 : 0xF8F9;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level", isBigEndian ? 0x067F : 0x067E },
                    { "trigger", isBigEndian ? 0xF2FC : 0xF2FD },
                    { "menuoption", isBigEndian ? 0xFF69 : 0xFF68 },
                    { "gamemode", isBigEndian ? 0x3CB7 : 0x3CB6 },
                    { "levelselect", vars.levelselectoffset }

                });
                vars.addUShortAddresses(new Dictionary<string, long>() {
                    { "menutimeout", 0xFF6C }
                });

                vars.lastmenuoption = 999;
                vars.skipsplit = false;
            }
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

        case "Sonic Chaos":
            const string 
                TURQUOISE_HILL_1   = "0-0", TURQUOISE_HILL_2   = "0-1", TURQUOISE_HILL_3   = "0-2",
                GIGALOPOLIS_1      = "1-0", GIGALOPOLIS_2      = "1-1", GIGALOPOLIS_3      = "1-2",
                SLEEPING_EGG_1     = "2-0", SLEEPING_EGG_2     = "2-1", SLEEPING_EGG_3     = "2-2",
                MECHA_GREEN_HILL_1 = "3-0", MECHA_GREEN_HILL_2 = "3-1", MECHA_GREEN_HILL_3 = "3-2",
                AQUA_PLANET_1      = "4-0", AQUA_PLANET_2      = "4-1", AQUA_PLANET_3      = "4-2",
                ELECTRIC_EGG_1     = "5-0", ELECTRIC_EGG_2     = "5-1", ELECTRIC_EGG_3     = "5-2",
                AFTER_ELECTRIC_EGG_3 = "99-0";
            if ( watchercount == 0 ) {
                vars.isSMS = true;
                byte extraGGOffset = 0x0;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "platform", 0x111E }
                });

                vars.watchers["platform"].Update(game);
                switch( (int) vars.watchers["platform"].Current ) {
                    case 0x06: 
                        extraGGOffset = 0x02;
                        break;
                    case 0x26:
                        // Master System
                        break;
                    default:
                        vars.DebugOutput(String.Format("Can't Determine platform for Sonic Chaos {0}", vars.watchers["platform"].Current ));
                        vars.watchers =  new MemoryWatcherList {};
                        return false;
                }
                vars.levelselectoffset = 0x12CE + extraGGOffset;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level", 0x12C9 + extraGGOffset },
                    { "zone", 0x1297 + extraGGOffset },
                    { "act", 0x1298 + extraGGOffset },
                    { "lives", 0x1299 + extraGGOffset },
                    { "continues", 0x12C3 + extraGGOffset },
                    { "endBoss", 0x13E7 },
                    { "trigger", 0x03C1  },
                    { "levelselect", vars.levelselectoffset }
                });

                vars.expectednextlevel = new Dictionary<string, string>() {
                    { TURQUOISE_HILL_1,      /* -> */ TURQUOISE_HILL_2 },
                    { TURQUOISE_HILL_2,      /* -> */ TURQUOISE_HILL_3 },
                    { TURQUOISE_HILL_3,      /* -> */ GIGALOPOLIS_1 },
                    { GIGALOPOLIS_1,         /* -> */ GIGALOPOLIS_2 },
                    { GIGALOPOLIS_2,         /* -> */ GIGALOPOLIS_3 },
                    { GIGALOPOLIS_3,         /* -> */ SLEEPING_EGG_1 },
                    { SLEEPING_EGG_1,        /* -> */ SLEEPING_EGG_2 },
                    { SLEEPING_EGG_2,        /* -> */ SLEEPING_EGG_3 },
                    { SLEEPING_EGG_3,        /* -> */ MECHA_GREEN_HILL_1 },
                    { MECHA_GREEN_HILL_1,    /* -> */ MECHA_GREEN_HILL_2 },
                    { MECHA_GREEN_HILL_2,    /* -> */ MECHA_GREEN_HILL_3 },
                    { MECHA_GREEN_HILL_3,    /* -> */ AQUA_PLANET_1 },
                    { AQUA_PLANET_1,         /* -> */ AQUA_PLANET_2 },
                    { AQUA_PLANET_2,         /* -> */ AQUA_PLANET_3 },
                    { AQUA_PLANET_3,         /* -> */ ELECTRIC_EGG_1 },
                    { ELECTRIC_EGG_1,        /* -> */ ELECTRIC_EGG_2 },
                    { ELECTRIC_EGG_2,        /* -> */ ELECTRIC_EGG_3 },
                    { ELECTRIC_EGG_3,        /* -> */ AFTER_ELECTRIC_EGG_3 }
                };
                vars.isSonicChaos = true;
                
            }

            goto case "GenericNextLevelSplitter";

        case "Sonic Triple Trouble":
            const string 
                GREAT_TURQUOISE_1 = "0-0", GREAT_TURQUOISE_2 = "0-1", GREAT_TURQUOISE_3 = "0-2", 
                SUNSET_PARK_1 = "1-0",     SUNSET_PARK_2 = "1-1",     SUNSET_PARK_3 = "1-2",
                META_JUNGLIRA_1 = "2-0",   META_JUNGLIRA_2 = "2-1",   META_JUNGLIRA_3 = "2-2",
                ROBOTNIK_WINTER_1 = "3-0", ROBOTNIK_WINTER_2 = "3-1", ROBOTNIK_WINTER_3 = "3-2",
                TIDAL_PLANT_1 = "4-0",     TIDAL_PLANT_2 = "4-1",     TIDAL_PLANT_3 = "4-2",ATOMIC_DESTROYER_1 = "5-0", ATOMIC_DESTROYER_2 = "5-1",
                ATOMIC_DESTROYER_3 = "5-2",   AFTER_ATOMIC_DESTROYER_3 = "99-0";
            if ( watchercount == 0 ) {
                vars.isSMS = true;

                vars.levelselectoffset = 0x1C98;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level",      0x12C9 },
                    { "zone",       0x1145 },
                    { "act",        0x1147 },
                    { "lives",      0x1140 },
                    { "continues",  0x114B },
                    { "endBoss",    0x14F0 },
                    { "trigger",    0x1FEB },
                    { "levelselect", vars.levelselectoffset }
                });


                vars.expectednextlevel = new Dictionary<string, string>() {
                    { GREAT_TURQUOISE_1,    /* -> */ GREAT_TURQUOISE_2 },
                    { GREAT_TURQUOISE_2,    /* -> */ GREAT_TURQUOISE_3 },
                    { GREAT_TURQUOISE_3,    /* -> */ SUNSET_PARK_1 },
                    { SUNSET_PARK_1,        /* -> */ SUNSET_PARK_2 },
                    { SUNSET_PARK_2,        /* -> */ SUNSET_PARK_3 },
                    { SUNSET_PARK_3,        /* -> */ META_JUNGLIRA_1 },
                    { META_JUNGLIRA_1,      /* -> */ META_JUNGLIRA_2 },
                    { META_JUNGLIRA_2,      /* -> */ META_JUNGLIRA_3 },
                    { META_JUNGLIRA_3,      /* -> */ ROBOTNIK_WINTER_1 },
                    { ROBOTNIK_WINTER_1,    /* -> */ ROBOTNIK_WINTER_2 },
                    { ROBOTNIK_WINTER_2,    /* -> */ ROBOTNIK_WINTER_3 },
                    { ROBOTNIK_WINTER_3,    /* -> */ TIDAL_PLANT_1 },
                    { TIDAL_PLANT_1,        /* -> */ TIDAL_PLANT_2 },
                    { TIDAL_PLANT_2,        /* -> */ TIDAL_PLANT_3 },
                    { TIDAL_PLANT_3,        /* -> */ ATOMIC_DESTROYER_1 },
                    { ATOMIC_DESTROYER_1,   /* -> */ ATOMIC_DESTROYER_2 },
                    { ATOMIC_DESTROYER_2,   /* -> */ ATOMIC_DESTROYER_3 },
                    { ATOMIC_DESTROYER_3,   /* -> */ AFTER_ATOMIC_DESTROYER_3 }
                };
                vars.startTrigger = 0x21;
            }
            goto case "GenericNextLevelSplitter";
        /**********************************************************************************
            ANCHOR START Sonic the Hedgehog 1 & 2 Genesis & 2 8 bit support
        **********************************************************************************/
        case "Sonic the Hedgehog 2 (Game Gear / Master System)":
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
            if ( watchercount == 0 ) {
                vars.levelselectbytes = new byte[] {0x0D};
                vars.levelselectoffset = 0x112C;
                vars.emeraldcountoffset = 0x12BD;
                vars.emeraldflagsoffset = 0x12C5;
                vars.startTrigger = 68;
                vars.isSMSGGSonic2 = true;
                vars.isSMS = true;
                vars.isIGT = true;
                vars.hasRTATB = false;
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "seconds",      0x12B9 },
                    { "minutes",      0x12BA },
                    { "lives",        0x1298 },
                    { "continues",    0x1298 },
                    { "zone",         0x1295 },
                    { "act",          0x1296 },
                    { "trigger",      0x1293 },
                    { "systemflag",   0x12C8 },
                    { "levelselect",  vars.levelselectoffset },
                    { "emeraldcount", vars.emeraldcountoffset },
                    { "emeraldflags", vars.emeraldflagsoffset }
                });

                vars.addUShortAddresses(new Dictionary<string, long>() {
                    { "levelframecount",    0x12BA },
                    { "timebonus",          0x12A2 }
                });
                
                
                

                vars.expectednextlevel = new Dictionary<string, string>() {
                    { UNDER_GROUND_1,       /* -> */ UNDER_GROUND_2 },
                    { UNDER_GROUND_2,       /* -> */ UNDER_GROUND_3 },
                    { UNDER_GROUND_3,       /* -> */ SKY_HIGH_1 },
                    { SKY_HIGH_1,           /* -> */ SKY_HIGH_2 },
                    { SKY_HIGH_2,           /* -> */ SKY_HIGH_3 },
                    { SKY_HIGH_3,           /* -> */ AQUA_LAKE_1 },
                    { AQUA_LAKE_1,          /* -> */ AQUA_LAKE_2 },
                    { AQUA_LAKE_2,          /* -> */ AQUA_LAKE_3 },
                    { AQUA_LAKE_3,          /* -> */ GREEN_HILLS_1 },
                    { GREEN_HILLS_1,        /* -> */ GREEN_HILLS_2 },
                    { GREEN_HILLS_2,        /* -> */ GREEN_HILLS_3 },
                    { GREEN_HILLS_3,        /* -> */ GIMMICK_MT_1 },
                    { GIMMICK_MT_1,         /* -> */ GIMMICK_MT_2 },
                    { GIMMICK_MT_2,         /* -> */ GIMMICK_MT_3 },
                    { GIMMICK_MT_3,         /* -> */ SCRAMBLED_EGG_1 },
                    { SCRAMBLED_EGG_1,      /* -> */ SCRAMBLED_EGG_2 },
                    { SCRAMBLED_EGG_2,      /* -> */ SCRAMBLED_EGG_3 },
                    { SCRAMBLED_EGG_3,      /* -> */ CRYSTAL_EGG_1 },
                    { CRYSTAL_EGG_1,        /* -> */ CRYSTAL_EGG_2 },
                    { CRYSTAL_EGG_2,        /* -> */ CRYSTAL_EGG_3 },
                    { CRYSTAL_EGG_3,        /* -> */ S2SMS_GOOD_CREDITS },
                    { S2SMS_GOOD_CREDITS,   /* -> */ S2SMS_END }
                };
                return false;
            }
                
            if ( vars.watchers["trigger"].Changed ) {
                switch ( (uint) vars.watchers["trigger"].Current ) {
                    case 0x00:
                    case 0x40:
                        vars.watchers["seconds"].Enabled = true;
                        
                        break;
                    case 0x44:
                        vars.watchers["seconds"].Enabled = false;
                        vars.watchers["timebonus"].Enabled = false;
                        break;
                    case 0x50:
                    case 0x60:
                        vars.watchers["seconds"].Enabled = false;
                        vars.watchers["timebonus"].Enabled = true;
                        break;
                }
                vars.DebugOutput( String.Format( "Trigger now: {0:X} was: {1:X}", vars.watchers["trigger"].Current, vars.watchers["trigger"].Old));
            }

            if ( vars.watchers["timebonus"].Changed && 
                ( ( vars.nextsplit == CRYSTAL_EGG_1 && vars.watchers["emeraldflags"].Current < 0x3F ) || vars.nextsplit == S2SMS_GOOD_CREDITS ) 
            ) {
                split = true;
                
            }
            

            if ( !vars.ingame && 
                vars.watchers["trigger"].Current == vars.startTrigger && 
                vars.watchers["act"].Current == 0 && 
                vars.watchers["zone"].Current == 0 
            ) {
                vars.nextsplit = "0-1"; // 2nd Level
                vars.igttotal = 0;
                vars.juststarted = true;
                start = true;
                
                
            }
            if (
                !settings["levelselect"] &&
                vars.watchers["lives"].Current == 0 && 
                vars.watchers["continues"].Current == 0
            ) {
                reset = true;
            }
            
            currentlevel = String.Format("{0}-{1}", vars.watchers["zone"].Current, vars.watchers["act"].Current);
            if ( vars.nextsplit == currentlevel ) {
                vars.nextsplit = vars.expectednextlevel[currentlevel];
                vars.DebugOutput("Next Split on: " + vars.nextsplit);
                split = true;
                
            }
            if ( currentlevel == "7-0" && vars.nextsplit == "6-0") {
                split = true;
            }
            
            if ( 
                vars.nextsplit == "99-0" && 
                vars.watchers["trigger"].Current == 0x20 
            )  {
                split = true;
            }

            if ( vars.watchers["seconds"].Changed || vars.watchers["minutes"].Changed ) {

                var oldSeconds = vars.watchers["seconds"].Old;
                var curSeconds = vars.watchers["seconds"].Current;
                
                oldSeconds = ( ( oldSeconds >> 4 ) * 10 ) + ( oldSeconds & 0xF );
                curSeconds = ( ( curSeconds >> 4 ) * 10 ) + ( curSeconds & 0xF );
            
                if (
                    (
                        vars.watchers["seconds"].Changed &&
                        curSeconds == oldSeconds + 1
                    ) || (
                        vars.watchers["minutes"].Changed && vars.watchers["minutes"].Current == (vars.watchers["minutes"].Old + 1) &&
                        vars.watchers["seconds"].Current == 0 
                    )
                ) {
                    vars.igttotal++;
                }
            }
            gametime = TimeSpan.FromSeconds(vars.igttotal);
            break;
        
        case "Sonic the Hedgehog (Genesis / Mega Drive)":
            const string 
                GREEN_HILL_1  = "0-0", GREEN_HILL_2  = "0-1", GREEN_HILL_3  = "0-2",
                MARBLE_1      = "2-0", MARBLE_2      = "2-1", MARBLE_3      = "2-2",
                SPRING_YARD_1 = "4-0", SPRING_YARD_2 = "4-1", SPRING_YARD_3 = "4-2", 
                LABYRINTH_1   = "1-0", LABYRINTH_2   = "1-1", LABYRINTH_3   = "1-2", 
                STAR_LIGHT_1  = "3-0", STAR_LIGHT_2  = "3-1", STAR_LIGHT_3  = "3-2", 
                SCRAP_BRAIN_1 = "5-0", SCRAP_BRAIN_2 = "5-1", SCRAP_BRAIN_3 = "1-3", // LUL
                FINAL_ZONE    = "5-2", AFTER_FINAL_ZONE = "99-0"; 
            if ( watchercount == 0 ) {
                vars.expectednextlevel = new Dictionary<string, string>() {
                    { GREEN_HILL_1,     /* -> */ GREEN_HILL_2 },
                    { GREEN_HILL_2,     /* -> */ GREEN_HILL_3 },
                    { GREEN_HILL_3,     /* -> */ MARBLE_1 },
                    { MARBLE_1,         /* -> */ MARBLE_2 },
                    { MARBLE_2,         /* -> */ MARBLE_3 },
                    { MARBLE_3,         /* -> */ SPRING_YARD_1 },
                    { SPRING_YARD_1,    /* -> */ SPRING_YARD_2 },
                    { SPRING_YARD_2,    /* -> */ SPRING_YARD_3 },
                    { SPRING_YARD_3,    /* -> */ LABYRINTH_1 },
                    { LABYRINTH_1,      /* -> */ LABYRINTH_2 },
                    { LABYRINTH_2,      /* -> */ LABYRINTH_3 },
                    { LABYRINTH_3,      /* -> */ STAR_LIGHT_1 },
                    { STAR_LIGHT_1,     /* -> */ STAR_LIGHT_2 },
                    { STAR_LIGHT_2,     /* -> */ STAR_LIGHT_3 },
                    { STAR_LIGHT_3,     /* -> */ SCRAP_BRAIN_1 },
                    { SCRAP_BRAIN_1,    /* -> */ SCRAP_BRAIN_2 },
                    { SCRAP_BRAIN_2,    /* -> */ SCRAP_BRAIN_3 },
                    { SCRAP_BRAIN_3,    /* -> */ FINAL_ZONE },
                    { FINAL_ZONE,       /* -> */ AFTER_FINAL_ZONE }
                };
                
                vars.levelselectoffset = isBigEndian ? 0xFFE0 : 0xFFE1 ;
                vars.isGenSonic1 = true;
            }
            goto case "Sonic the Hedgehog 2 (Genesis / Mega Drive)";
        case "Sonic the Hedgehog 2 (Genesis / Mega Drive)":
            if ( !vars.isGenSonic1 && watchercount == 0 ) {
                vars.levelselectoffset = isBigEndian ? 0xFFD0 : 0xFFD1;

                const string 
                    EMERALD_HILL_1   =  "0-0", EMERALD_HILL_2   =  "0-1", 
                    CHEMICAL_PLANT_1 = "13-0", CHEMICAL_PLANT_2 = "13-1", 
                    AQUATIC_RUIN_1   = "15-0", AQUATIC_RUIN_2   = "15-1", 
                    CASINO_NIGHT_1   = "12-0", CASINO_NIGHT_2   = "12-1",
                    HILL_TOP_1       =  "7-0", HILL_TOP_2       =  "7-1", 
                    MYSTIC_CAVE_1    = "11-0", MYSTIC_CAVE_2    = "11-1", 
                    OIL_OCEAN_1      = "10-0", OIL_OCEAN_2      = "10-1", 
                    METROPOLIS_1     =  "4-0", METROPOLIS_2     =  "4-1", METROPOLIS_3 =  "5-0", 
                    SKY_CHASE        = "16-0", WING_FORTRESS    =  "6-0", S2_DEATH_EGG    = "14-0", 
                    AFTER_DEATH_EGG = "99-0";

                vars.expectednextlevel = new Dictionary<string, string>() {
                    { EMERALD_HILL_1,   /* -> */ EMERALD_HILL_2 },
                    { EMERALD_HILL_2,   /* -> */ CHEMICAL_PLANT_1 },
                    { CHEMICAL_PLANT_1, /* -> */ CHEMICAL_PLANT_2 },
                    { CHEMICAL_PLANT_2, /* -> */ AQUATIC_RUIN_1 },
                    { AQUATIC_RUIN_1,   /* -> */ AQUATIC_RUIN_2 },
                    { AQUATIC_RUIN_2,   /* -> */ CASINO_NIGHT_1 },
                    { CASINO_NIGHT_1,   /* -> */ CASINO_NIGHT_2 },
                    { CASINO_NIGHT_2,   /* -> */ HILL_TOP_1 },
                    { HILL_TOP_1,       /* -> */ HILL_TOP_2 },
                    { HILL_TOP_2,       /* -> */ MYSTIC_CAVE_1 },
                    { MYSTIC_CAVE_1,    /* -> */ MYSTIC_CAVE_2 },
                    { MYSTIC_CAVE_2,    /* -> */ OIL_OCEAN_1 },
                    { OIL_OCEAN_1,      /* -> */ OIL_OCEAN_2 },
                    { OIL_OCEAN_2,      /* -> */ METROPOLIS_1 },
                    { METROPOLIS_1,     /* -> */ METROPOLIS_2 },
                    { METROPOLIS_2,     /* -> */ METROPOLIS_3 },
                    { METROPOLIS_3,     /* -> */ SKY_CHASE },
                    { SKY_CHASE,        /* -> */ WING_FORTRESS },
                    { WING_FORTRESS,    /* -> */ S2_DEATH_EGG },
                    { S2_DEATH_EGG,     /* -> */ AFTER_DEATH_EGG }
                };
            }
            if ( watchercount == 0 ) {
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "seconds", isBigEndian ? 0xFE24 : 0xFE25 },
                    { "minutes", isBigEndian ? 0xFE23 : 0xFE22 },
                    { "lives",   isBigEndian ? 0xFE12 : 0xFE13 },
                    { "continues", isBigEndian ? 0xFE18 : 0xFE19 },
                    { "zone", isBigEndian ? 0xFE10 : 0xFE11 },
                    { "act", isBigEndian ? 0xFE11 : 0xFE10 },
                    { "trigger", isBigEndian ? 0xF600 : 0xF601 },
                    { "levelselect", vars.levelselectoffset }
                });

                vars.addUShortAddresses(new Dictionary<string, long>() {
                    { "timebonus", 0xF7D2 },
                    { "levelframecount", isBigEndian ? 0xFE05 : 0xFE04 }

                });
                vars.addULongAddresses(new Dictionary<string, long>() {
                    { "fadeout", 0xFB00 }
                });

                

                vars.isGenSonic1or2 = true;
                vars.isIGT = true;
                vars.hasRTATB = true;
                return false;
            }
            goto case "GenericNextLevelSplitter";
        case "Sonic CD":
            var addmsandreset = false;
            if ( watchercount == 0 ) {
                const string 
                    PALMTREE_PANIC_1    = "0-0", PALMTREE_PANIC_2    = "0-1", PALMTREE_PANIC_3    = "0-2",
                    COLLISION_CHAOS_1   = "1-0", COLLISION_CHAOS_2   = "1-1", COLLISION_CHAOS_3   = "1-2",
                    TIDAL_TEMPEST_1     = "2-0", TIDAL_TEMPEST_2     = "2-1", TIDAL_TEMPEST_3     = "2-2",
                    QUARTZ_QUADRANT_1   = "3-0", QUARTZ_QUADRANT_2   = "3-1", QUARTZ_QUADRANT_3   = "3-2", 
                    WACKY_WORKBENCH_1   = "4-0", WACKY_WORKBENCH_2   = "4-1", WACKY_WORKBENCH_3   = "4-2", 
                    STARDUST_SPEEDWAY_1 = "5-0", STARDUST_SPEEDWAY_2 = "5-1", STARDUST_SPEEDWAY_3 = "5-2", 
                    METALLIC_MADNESS_1  = "6-0", METALLIC_MADNESS_2  = "6-1", METALLIC_MADNESS_3  = "6-2", 
                    AFTER_METALLIC_MADNESS_3 = "99-0";
                
                vars.expectednextlevel = new Dictionary<string, string>() {
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

                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "seconds",                isBigEndian ? 0x1516 : 0x1517 },
                    { "minutes",                isBigEndian ? 0x1515 : 0x1514 },
                    { "lives",                  isBigEndian ? 0x1508 : 0x1509 },
                    { "continues",              isBigEndian ? 0x1508 : 0x1509 },
                    { "zone",                   isBigEndian ? 0x1506 : 0x1507 },
                    { "act",                    isBigEndian ? 0x1507 : 0x1506 },
                    { "trigger",                isBigEndian ? 0xFA0E : 0xFA0F },
                    { "timeperiod",             isBigEndian ? 0x152E : 0x152F },
                    { "framesinsecond",         isBigEndian ? 0x1517 : 0x1516 },
                    { "timewarpminutes",        isBigEndian ? 0x1571 : 0x1570 },
                    { "timewarpseconds",        isBigEndian ? 0x1572 : 0x1573 },
                    { "timewarpframesinsecond", isBigEndian ? 0x1573 : 0x1572 },
                    { "levelframecount",        isBigEndian ? 0x1505 : 0x1504 }


                });


                vars.addUShortAddresses(new Dictionary<string, long>() { 
                    { "timebonus", 0xF7D2 }
                });
                vars.addULongAddresses(new Dictionary<string, long>() {
                    { "fadeout", 0xFB00 }
                });
                vars.isIGT = true;
                vars.hasRTATB = true;
                
                vars.startTrigger = 1;
                vars.ms = 0;
                vars.wait = false;
                vars.isSonicCD = true;
                current.cdloading = false;
                foreach ( var watcher in vars.watchers ) {
                    if ( watcher.Name != "trigger" && watcher.Name != "timeperiod" ) {
                        watcher.Enabled = false;
                        watcher.Reset();
                    }
                }
                return false;
            }

            var scdtrigger = vars.watchers["trigger"];
            var scdtimeperiod = vars.watchers["timeperiod"];
            var scdlevelframecount = vars.watchers["levelframecount"];
            var scdminutes = vars.watchers["minutes"];
            var scdzone = vars.watchers["zone"];
            var scdact = vars.watchers["act"];
            var scdlives = vars.watchers["lives"];
            var scdseconds = vars.watchers["seconds"];
            var scdframesinsecond = vars.watchers["framesinsecond"];
            var scdtimewarpseconds = vars.watchers["timewarpseconds"];
            var scdtimewarpframesinsecond = vars.watchers["timewarpframesinsecond"];
            var scdtimewarpminutes = vars.watchers["timewarpminutes"];
            var scdfadeout = vars.watchers["fadeout"];
            var scdtimebonus = vars.watchers["timebonus"];
            if ( scdtrigger.Changed || scdtimeperiod.Changed ) {
                if ( settings["extralogging"] ) {
                    vars.DebugOutput(String.Format("Trigger was: {0:X} now: {1:X}, Time period was: Trigger was: {2:X} now: {3:X}", scdtrigger.Old, scdtrigger.Current,scdtimeperiod.Old, scdtimeperiod.Current  ) );
                }
                if ( !vars.ingame && scdtimeperiod.Current == 1 && scdtrigger.Current == 1 ) {
                    start = true;
                    scdlevelframecount.Enabled = true;
                    scdzone.Enabled = true;
                    scdact.Enabled = true;
                    scdlives.Enabled = true;
                    vars.nextsplit = "0-1";
                    current.totalseconds = 0;
                    current.expectedms = 0;
                    current.cdloading = false;
                }
                if ( scdtimeperiod.Current >= 0x80 && scdtimeperiod.Old < 0x80 ) {
                    scdminutes.Enabled = false;
                    scdseconds.Enabled = false;
                    scdframesinsecond.Enabled = false;
                    scdseconds.Current = scdtimewarpseconds.Current;
                    scdframesinsecond.Current = scdtimewarpframesinsecond.Current;
                }
                if ( scdtimeperiod.Current < 0x80 && scdtimeperiod.Old >= 0x80 ) {
                    scdminutes.Enabled = true;
                    scdseconds.Enabled = true;
                    scdframesinsecond.Enabled = true;
                }
            }
            if ( vars.ingame ) {
                if ( scdlevelframecount.Changed && scdlevelframecount.Current <= 1 ) {
                    current.cdloading = false;
                    scdseconds.Enabled = true;
                    scdminutes.Enabled = true;
                    scdframesinsecond.Enabled = true;
                    scdtimebonus.Enabled = true;
                }

                if ( scdseconds.Changed && scdseconds.Current > 0 ) {
                    scdlevelframecount.Enabled = false;
                    scdtimewarpminutes.Enabled = true;
                    scdtimewarpseconds.Enabled = true;
                    scdtimewarpframesinsecond.Enabled = true;
                }

                if ( vars.nextsplit == "99-0" ) {
                    scdfadeout.Enabled = true;
                    if (
                                (scdfadeout.Current == 0xEE0EEE0EEE0EEE0E && scdfadeout.Old == 0xEE0EEE0EEE0EEE0E) ||
                                (scdfadeout.Current == WHITEOUT && scdfadeout.Old == WHITEOUT)
                    )  {
                        split = true;
                    }
                }

                if ( scdframesinsecond.Enabled ) {
                    current.totalseconds = ( scdminutes.Current * 60) + scdseconds.Current;

                    vars.igttotal += Math.Max(current.totalseconds - old.totalseconds,0) * 1000;
                    current.expectedms = Math.Floor(scdframesinsecond.Current * (100.0/6.0));

                    vars.ms = Math.Max(current.expectedms, 0);

                    if ( scdlives.Current == scdlives.Old -1 ) {
                        addmsandreset = true;
                    }
                }
                currentlevel = String.Format("{0}-{1}", scdzone.Current, scdact.Current);
                if ( vars.nextsplit == currentlevel ) {
                    vars.nextsplit = vars.expectednextlevel[currentlevel];
                    vars.DebugOutput("Next Split on: " + vars.nextsplit);


                    
                    addmsandreset = true;
                    split = true;

                }

            }
            if ( addmsandreset ) {
                scdseconds.Enabled = false;
                scdlevelframecount.Enabled = true;
                scdframesinsecond.Enabled = false;
                scdframesinsecond.Current = 0;
                vars.igttotal += old.expectedms;
                vars.ms = 0;
                current.expectedms = 0;
                addmsandreset = false;
            }
            gametime = TimeSpan.FromMilliseconds(vars.igttotal + vars.ms);
            break;
        case "GenericNextLevelSplitter":

            if ( vars.isIGT && vars.watchers["levelframecount"].Changed && vars.watchers["levelframecount"].Current <= 1 ) {
                vars.watchers["seconds"].Enabled = true;
                vars.watchers["timebonus"].Enabled = true;
            }
            if ( vars.isIGT && vars.watchers["seconds"].Changed && vars.watchers["seconds"].Current == 1 ) {
                vars.watchers["levelframecount"].Enabled = false;
            }
            
            if ( !vars.ingame && 
                ( 
                    ( !vars.isSonicChaos && vars.watchers["trigger"].Current == vars.startTrigger ) ||
                    ( vars.isSonicChaos && ( vars.watchers["lives"].Old == 0 && vars.watchers["lives"].Current >= 3 ) )
                 ) && 
                vars.watchers["act"].Current == 0 && 
                vars.watchers["zone"].Current == 0 
            ) {
                vars.nextsplit = "0-1"; // 2nd Level
                if ( vars.isIGT ) { 
                    vars.watchers["seconds"].Enabled = false;
                    vars.watchers["levelframecount"].Enabled = true;
                }
                
                start = true;
                vars.igttotal = 0;
                current.totalseconds = 0;
                
            }
            if ( 
                !settings["levelselect"] && 
                (
                    (  vars.watchers["lives"].Current == 0 && vars.watchers["continues"].Current == 0 ) ||
                    ( vars.watchers["trigger"].Current == 0x04 && vars.watchers["trigger"].Old == 0x0 ) 
                )
            ) {
                reset = true;
            }
            currentlevel = String.Format("{0}-{1}", vars.watchers["zone"].Current, vars.watchers["act"].Current);
            if ( vars.nextsplit == currentlevel ) {
                vars.nextsplit = vars.expectednextlevel[currentlevel];
                vars.DebugOutput("Next Split on: " + vars.nextsplit);
                if ( vars.isIGT ) {
                    vars.watchers["seconds"].Enabled = false;
                    vars.watchers["levelframecount"].Enabled = true;
                }
                split = true;
            }
            if ( vars.isSonicChaos && currentlevel == "5-2" && vars.watchers["endBoss"].Current == 255) {
                Thread.Sleep( 3 * (1/60) );
                split = true;
            }
            if ( 
                vars.nextsplit == "99-0" && (
                    ( vars.isGenSonic1 && vars.watchers["trigger"].Current == 0x18 ) ||
                    ( !vars.isGenSonic1 && vars.watchers["trigger"].Current == 0x20 )
                    
                )
            )  {
                split = true;
            }

            if ( !vars.isIGT ) {
                break;
            }
            if ( vars.ingame && ( !vars.isGenSonic1or2 || vars.watchers["trigger"].Current == 0x0C ) ) {
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
            
            gametime = TimeSpan.FromSeconds(vars.igttotal);

            break;
        /**********************************************************************************
            ANCHOR START Sonic the Hedgehog 3 & Knuckles split code
        **********************************************************************************/

            case "SetupS3K":
                const byte ACT_1 = 0, ACT_2 = 1,
                    SONIC_AND_TAILS = 0, SONIC = 1, TAILS = 2, KNUCKLES = 3;

                /* S3K levels */
                const byte 
                    ANGEL_ISLAND      = 0, SANDOPOLIS        = 8,
                    HYDROCITY         = 1, LAVA_REEF         = 9,
                    MARBLE_GARDEN     = 2, SKY_SANCTUARY     = 10,
                    CARNIVAL_NIGHT    = 3, DEATH_EGG         = 11,
                    ICE_CAP           = 5, DOOMSDAY          = 12,
                    LAUNCH_BASE       = 6, LRB_HIDDEN_PALACE = 22,
                    MUSHROOM_HILL     = 7, DEATH_EGG_BOSS    = 23,
                    FLYING_BATTERY    = 4, S3K_CREDITS       = 13;
                
                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "zone", isBigEndian ? 0xEE4E : 0xEE4F },
                    { "act",  isBigEndian ? 0xEE4F : 0xEE4E },
                    { "reset", 0xFFFC },
                    { "trigger", isBigEndian ? 0xF600 : 0xF601 },
                    
                    { "chara", isBigEndian ? 0xFF09 : 0xFF08 },
                    { "ddzboss", isBigEndian ? 0xB1E5 : 0xB1E4 },
                    { "sszboss", isBigEndian ? 0xB279 : 0xB278 },
                    { "delactive", isBigEndian ? 0xEEE4 : 0xEEE5 },
                    { "savefile", isBigEndian ? 0xEF4B : 0xEF4A },
                    { "savefilezone", isBigEndian ? 0xFDEB : 0xFDEA },
                    { "s3savefilezone", isBigEndian ? 0xB15F : 0xB15E },
                    { "levelselect", vars.levelselectoffset },
                    { "endlevelflag", 0xFAA8 },
                    { "starpostid", 0xFE2B },

                    { "chaosemeralds", 0xFFB0 },

                    { "superemeralds", 0xFFB1 }
                    /* $FFA6-$FFA9  Level number in Blue Sphere  */
                    /* $FFB0 	Number of chaos emeralds  */
                    /* $FFB1 	Number of super emeralds  */ 
                    /* $FFB2-$FFB8 	Array of finished special stages. Each byte represents one stage: 
            
                        0 - special stage not completed 
                        1 - chaos emerald collected 
                        2 - super emerald present but grayed 
                        3 - super emerald present and activated  
                    */ 

                });
                vars.addUShortAddresses(new Dictionary<string, long>() {
                    { "timebonus", 0xF7D2 },
                    { "leftboundary", 0xEE14 },

                });

                vars.addULongAddresses(new Dictionary<string, long>() {
                    { "primarybg", 0xFC00 }
                });

                foreach ( var watcher in vars.watchers ) {
                    if ( watcher.Name != "trigger" ) {
                        watcher.Enabled = false;
                        watcher.Reset();
                    }
                }
                current.primarybg  = 0;
                vars.expectedzone = 0;
                vars.expectedact = 1;
                vars.sszsplit = false; //boss is defeated twice
                vars.savefile = 255;
                vars.skipsAct1Split = false;
                vars.specialstagetimer = new Stopwatch(); 
                vars.addspecialstagetime = false; 
                vars.specialstagetimeadded = false; 
                vars.gotEmerald = false;
                vars.chaoscatchall = false;
                vars.chaossplits = 0;
                vars.hasRTATB = !vars.isAir;
                
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
                return false;
            case "Sonic 3 & Knuckles":
                if ( watchercount == 0 ) {
                    goto case "SetupS3K";
                }


                var trigger = vars.watchers["trigger"];
                var resettrigger = vars.watchers["reset"];
                var delactive = vars.watchers["delactive"];
                var zone = vars.watchers["zone"];
                var act = vars.watchers["act"];
                var primarybg = vars.watchers["primarybg"];
                var endlevelflag = vars.watchers["endlevelflag"];
                var starpostid = vars.watchers["starpostid"];
                var leftboundary = vars.watchers["leftboundary"];

                if ( primarybg.Changed ) {
                    current.primarybg = primarybg.Current;
                    if ( vars.isBigEndian ) {
                        current.primarybg = vars.SwapEndiannessLong(primarybg.Current);
                    }
                }
                var savefile = vars.watchers["savefile"];
                var savefilezone = ( vars.isS3 ? vars.watchers["s3savefilezone"] : vars.watchers["savefilezone"] );

                if ( settings["extralogging"] ) {
                    if ( endlevelflag.Changed ) {
                        vars.DebugOutput(String.Format("End Level Flag was: {0:X} now: {1:X}", endlevelflag.Old, endlevelflag.Current ) );
                    }
                    if ( starpostid.Changed ) {
                        vars.DebugOutput(String.Format("StarPost ID was: {0:X} now: {1:X}", starpostid.Old, starpostid.Current ) );
                    }

                    if ( leftboundary.Changed ) {
                        vars.DebugOutput(String.Format("leftboundary was: {0:X} now: {1:X}", leftboundary.Old, leftboundary.Current ) );
                    }
                }

                if ( starpostid.Changed && starpostid.Current != 0 ) {
                    vars.specialtriggercounter = -1;
                }

                if ( endlevelflag.Changed && endlevelflag.Current == 0xFF && vars.specialtriggercounter == 0 ) {
                    vars.specialtriggercounter = 1;
                }

                if ( leftboundary.Changed && vars.specialtriggercounter == 1) {
                    vars.specialtriggercounter = 2;
                }

                if ( trigger.Changed ) {
                    if ( settings["extralogging"] ) {
                        vars.DebugOutput(String.Format("Trigger was: {0:X} now: {1:X}", trigger.Old, trigger.Current ) );
                    }
                    switch ( (int) trigger.Current ) {
                        case 0x00: // Game init - Disable all watchers except trigger.
                            foreach ( var watcher in vars.watchers ) {
                                if ( watcher.Name != "trigger" ) {
                                    watcher.Enabled = vars.isAir;
                                    if ( vars.isAir && watcher.Name == "s3savefilezone" ) {
                                        watcher.Enabled = false;
                                    }
                                    watcher.Reset();
                                }
                            }
                            current.primarybg  = 0;
                            break;
                        case 0x04: // sega logo -> title screen
                            zone.Enabled = true;
                            act.Enabled = true;
                            vars.watchers["chara"].Enabled = true;
                            resettrigger.Enabled = settings["hard_reset"];
                            break;
                        case 0x4C: // data select screen
                            primarybg.Enabled = true;
                            savefile.Enabled = true;
                            savefilezone.Enabled = !vars.isSK;
                            delactive.Enabled = true;
                            zone.Enabled = true;
                            act.Enabled = true;
                            break;
                        case 0x8C: // start game
                            if ( vars.specialtriggercounter == 2 ) {
                                vars.DebugOutput("Y'know we should split for this" );
                                split = true;
                                vars.expectedzone = vars.expectedzonemap[zone.Current];
                                vars.expectedact = ACT_1;
                                vars.specialtriggercounter = -1;
                                break;
                            }
                            goto case 0x0C;
                        case 0x0C: // in level
                            if ( trigger.Old == 0x8C || trigger.Old == 0xC) {
                                break;
                            }
                            vars.savefile = savefile.Current;
                            vars.DebugOutput(String.Format("Start game {0} {1} {2:X}", zone.Current, act.Current, trigger.Old) );

                            primarybg.Enabled = false;
                            savefilezone.Enabled = false;
                            savefile.Enabled = false;
                            delactive.Enabled = false;
                            if ( !zone.Enabled ) {
                                zone.Enabled = true;
                                act.Enabled = true;
                                zone.Update(game);
                                act.Update(game);
                            }
                            if ( !vars.ingame && act.Current == 0 && 
                                ( 
                                    ( zone.Current == 0 && trigger.Old == 0x4C ) ||
                                    ( vars.isSK && zone.Current == 7 && trigger.Old == 0x04 )
                                )
                            ) {
                                    vars.expectedzone = zone.Current;
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
                                    start = true;
                            }
                            vars.watchers["timebonus"].Enabled = !vars.isAir;
                            vars.watchers["timebonus"].Update(game);
                            break;
                        /*case 0x0C: // in level
                            //vars.DebugOutput(String.Format("Enabling TB {0}", vars.hasRTATB ));

                            break;*/
                        case 0x34: // Go to special stage
                            if ( settings["pause_bs"] ) {
                                current.loading = true;
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
                    ( vars.isSK && !settings["levelselect"] && zone.Changed && act.Current == 0 && zone.Current == 0 ) ||
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
                                current.primarybg == 0x08AA0ACC0EEE0000
                            )
                        ) 
   
                    )
                ) {
                    reset = true;
                }

                if ( zone.Changed || act.Changed ) {
                    if ( !vars.watchers["timebonus"].Enabled && !vars.isAir ) {
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
                                vars.specialtriggercounter = 0;
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
                                vars.specialtriggercounter = -1;
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
                       (ulong) current.primarybg == WHITEOUT 
                    )
                    {
                        vars.DebugOutput("SS / LB2 Boss White Screen detected");
                        split = true;
                    }
                }
                

                if (vars.watchers["chara"].Current == KNUCKLES && zone.Current == SKY_SANCTUARY) //detect final hit on Knux Sky Sanctuary Boss
                {
                    vars.watchers["sszboss"].Enabled = true;
                    if (vars.watchers["sszboss"].Current == 0 && vars.watchers["sszboss"].Old == 1)
                    {
                        primarybg.Enabled = true;
                        vars.DebugOutput("Knuckles Final Boss 1st phase defeat detected");
                        vars.sszsplit = true;
                    }
                }

            break;
        case "Sonic 3 & Knuckles - Bonus Stages Only":
            if ( watchercount == 0 ) {
                goto case "SetupS3K";
            }
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
                                current.loading = true;
                                vars.juststarted = true;
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
                            current.primarybg == 0x08AA0ACC0EEE0000 &&
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
            if ( watchercount == 0 ) {
                vars.isSMS = true;
                //vars.ringsoffset = (IntPtr)smsMemoryOffset +  0x12AA;
                //vars.leveloffset = (IntPtr)smsMemoryOffset +  0x123E;

                vars.addByteAddresses(new Dictionary<string, long>() {
                    { "level", 0x123E },
                    { "state", 0x1000 },
                    { "input", 0x1203 },
                    { "endBoss", 0x12D5 },
                    { "scorescreen", 0x122C },
                    { "menucheck1", 0x1C08 },
                    { "menucheck2", 0x1C0A }
                });
                vars.addUIntAddresses(new Dictionary<string, long>() {
                    { "timebonus", 0x1212 }
                });

                vars.watchers["timebonus"].Enabled = false;
                
                vars.hasRTATB = true;
                vars.isSMSS1 = true;
                return false;
            }
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
                    vars.watchers["input"].Enabled = true;
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


    vars.SwapEndianness = (Func<ushort,ushort>)((value) => {
        var b1 = (value >> 0) & 0xff;
        var b2 = (value >> 8) & 0xff;

        return (ushort) (b1 << 8 | b2 << 0);
    });

    vars.SwapEndiannessInt = (Func<uint, uint>)((value) => {
        return ((value & 0x000000ff) << 24) +
            ((value & 0x0000ff00) << 8) +
            ((value & 0x00ff0000) >> 8) +
            ((value & 0xff000000) >> 24);
    });

    vars.SwapEndiannessIntAndTruncate = (Func<uint, uint>)((value) => {
        return ((value & 0x00000000) << 24) +
            ((value & 0x0000ff00) << 8) +
            ((value & 0x00ff0000) >> 8) +
            ((value & 0xff000000) >> 24);
    });

    vars.SwapEndiannessLong = (Func<ulong, ulong>)((value) => {
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
    });

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

    /* Cool Spot settings */

    settings.Add("coolspot", true, "Settings for Cool Spot");
    settings.Add("coolspot_split_on_cage_hit", true, "Split when cage lock is hit", "coolspot");
    settings.SetToolTip("coolspot_split_on_cage_hit", "If unchecked, split when the next level starts instead.");

    /* Earthworm Jim settings*/
    settings.Add("ewj1", true, "Settings for Earthworm Jim");
    settings.Add("ewj1_split", true, "Split", "ewj1");
    settings.Add("ewj1_split_andy", true, "Split after Andy asteroids levels", "ewj1_split");
    settings.Add("ewj1_split_evil_cat", false, "Split before the Evil the Cat section in What the heck?", "ewj1_split");
    settings.Add("ewj1_split_chicken", false, "Split before the Chicken fly section in Level 5", "ewj1_split");
    settings.Add("ewj1_split_helicopter", false, "Split after the helicopter section in Buttville", "ewj1_split");
    settings.Add("ewj1_split_snots", false, "Split after each fight in Snot a problem", "ewj1_split");
    settings.Add("ewj1_reset", true, "Reset", "ewj1");
    settings.Add("ewj1_reset_sega_logo", true, "Reset on SEGA logo", "ewj1_reset");
    settings.Add("ewj1_reset_cheat_menu", true, "Reset on entering the cheat menu", "ewj1_reset");

    /* Debug Settings */
    settings.Add("debug", false, "Debugging Options");
    settings.Add("levelselect", false, "Enable Level Select (if supported)", "debug");
    settings.Add("s2smsallemeralds", false, "S2SMS Enable All Emeralds", "debug");
    settings.Add("extralogging", false, "Extra detail for dev/debugging", "debug");

    settings.Add("rtatbinrta", false, "Store RTA-TB in Real-Time (only applies to non-IGT games)");

    vars.DebugOutput = (Action<string>)((text) => {
        string time = System.DateTime.Now.ToString("dd/MM/yy hh:mm:ss:fff");
        File.AppendAllText(logfile, "[" + time + "]: " + text + "\r\n");
        print("[SEGA Master Splitter] "+text);
    });
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
        return true;
    }
}

onReset
{
    vars.reInitialise();
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
    uint tmp = 0;
    if ( vars.hasRTATB ) {
        var timebonus = vars.watchers["timebonus"];

        if ( vars.triggerTB ) {
            timebonus.Update(game);
        }
        if ( timebonus.Changed || vars.triggerTB ) {
            
            uint ctb = timebonus.Current;
            tmp = timebonus.Current;
            if ( vars.isSMSGGSonic2 ) {
                ctb  = (uint) ( Int32.Parse(String.Format("{0:X8}", tmp) ) * (10/3.57) );
                vars.DebugOutput(String.Format("TB {0:X8}, {1} {1:X8}", tmp,ctb));
                vars.triggerTB = false;
            }
            if ( vars.isSMSS1 ) {
                tmp = vars.SwapEndiannessInt( timebonus.Current );
                if ( vars.isBigEndian  ) {
                    tmp = vars.SwapEndiannessIntAndTruncate( timebonus.Current );
                }
                ctb  = (uint) ( Int32.Parse(String.Format("{0:X8}", tmp)) / 10 );
                vars.DebugOutput(String.Format("TB {0:X8}, {1} {1:X8}", tmp,ctb));
                vars.triggerTB = false;
            } else if ( vars.isBigEndian ) {
                ctb  = vars.SwapEndianness(timebonus.Current);
            }
            if ( vars.isSonicCD ) {
                ctb = ctb / 10;
            }
            vars.DebugOutput(String.Format("TB {0:X8}, {1} {1:X8}", tmp,ctb));
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

    if ( ( settings["rtatbinrta"] || ( vars.isIGT && vars.hasRTATB ) ) && current.loading != old.loading ) {
        vars.timerModel.Pause(); // Pause/UnPause
    } 
    return vars.isIGT || current.loading;
}

gameTime
{
    if ( vars.juststarted ) {
        vars.juststarted = false;
        return TimeSpan.FromMilliseconds(0);
    }

    if ( vars.addspecialstagetime && !current.split ) { 
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
