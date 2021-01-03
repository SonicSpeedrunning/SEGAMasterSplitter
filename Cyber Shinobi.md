# Cyber Shinobi info

The Splitter looks mainly for Game State (address 0x0002), lives (address 0x000C) and current level (address 0x000C)

The time starts when current level is 0 and state is 17 (which corresponds to the brief black screen that appears before showing the current level info). A new split is performed when the level corresponds to next split and the state is 17. The last split is done when the state is 21 (which is the start of the ending cinematic which appears right after the last score screen).

## Useful ram addresses

| RAM address (HEX) | Value(s) (HEX) | Value(s) (DEC) | Description                                                           |
|------------------|----------------|----------------|-----------------------------------------------------------------------|
| 0002             | 01             | 01             | Game State: intro screen                                              |
| 0002             | 04             | 04             | Game State: Black screen before switching to the current level        |
| 0002             | 05             | 05             | Game State: in a level (gameplay)                                     |
| 0002             | 11             | 17             | Game State: Black screen that transitions to the level summary screen |
| 0002             | 12             | 18             | Game State: Level summary screen                                      |
| 0002             | 13             | 19             | Game State: Black screen that transitions to level end screen         |
| 0002             | 14             | 20             | Game State: Level end screen                                          |
| 0002             | 15             | 21             | Ending cinematic (or rather scrolling text XD)                        |
| 000C             | 00 to 05       | 00 to 05       | Current level (0 is level 1)                                          |
| 000E             | 00 to FF       | 00 to 255      | Number of lives                                                       |

## Useful links

- [Official Z80 docs](http://www.zilog.com/docs/z80/um0080.pdf)
- [Z80 wikibooks](https://fr.wikibooks.org/wiki/Programmation_Assembleur_Z80)
- [C# documentation for `tryParse`](https://docs.microsoft.com/fr-fr/dotnet/api/system.int32.tryparse?view=net-5.0#System_Int32_TryParse_System_String_System_Int32__)
- [Sysinternals suite DebugView (for debugging the script)](https://docs.microsoft.com/en-us/sysinternals/downloads/debugview)
- [Auto Splitting Language extension for VSCode](https://marketplace.visualstudio.com/items?itemName=B0sh.asl-extension)
- [Bookmarks VSCode extension](https://marketplace.visualstudio.com/items?itemName=alefragnani.Bookmarks)
- [Markdown table generator](https://www.tablesgenerator.com/markdown_tables)
- [SMS documents from SMSPower](https://www.smspower.org/Development/Documents). This [one](https://www.smspower.org/uploads/Development/richard.txt) for example
- [SMSpower memory hacks](https://www.smspower.org/Development/MemoryHacks)
- [SMSPower cheats for Cyber Shinobi](https://www.smspower.org/Cheats/CyberShinobi-SMS)
- [Livesplit FAQ](https://livesplit.org/faq/)
- [Emulicious SMS emulator which has powerful debugging tools](https://emulicious.net/)
- [Official ASL documentation](https://github.com/LiveSplit/LiveSplit.AutoSplitters/blob/master/README.md)