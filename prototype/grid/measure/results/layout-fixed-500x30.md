### Initial render

| rows x cols | variant | HTML KB | join frame KB | join gzip KB | interactive ms | settled ms |
| --- | --- | --- | --- | --- | --- | --- |
| 500 x 30 | keyed | 3695.5 | 1222.8 | 107.5 | 1028.9 | 1068.5 |
| 500 x 30 | streams | 3695.6 | 1234 | 109 | 1193.5 | 1448.6 |
| 500 x 30 | components | 3695.6 | 1288.2 | 117.3 | 1098.6 | 1139 |

### One cell edit saved

| rows x cols | variant | diff bytes | round trip ms | to next frame ms | server handle_event ms | of which re-fetch ms | of which Ash update ms | browser script ms | browser layout ms | browser style ms |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 500 x 30 | keyed | 235 | 144.9 | 236.8 | 10.8 | 0 | 10.5 | 40.9 | 10.3 | 21.7 |
| 500 x 30 | streams | 3361.5 | 145 | 240.4 | 18.7 | 9.7 | 9.5 | 29 | 11.3 | 25.4 |
| 500 x 30 | components | 173 | 123 | 218.8 | 10.1 | 0 | 9.9 | 10.4 | 11.4 | 24.8 |

### Sort click

| rows x cols | variant | diff KB | round trip ms | to next frame ms | browser script ms | browser layout ms |
| --- | --- | --- | --- | --- | --- | --- |
| 500 x 30 | keyed | 233.1 | 362.6 | 526.9 | 212.3 | 51 |
| 500 x 30 | streams | 1219.9 | 559.4 | 724.8 | 394.6 | 50.4 |
| 500 x 30 | components | 244.1 | 429.1 | 603.7 | 266.7 | 50.3 |

### Page change

| rows x cols | variant | diff KB | round trip ms | to next frame ms | browser script ms | browser layout ms |
| --- | --- | --- | --- | --- | --- | --- |
| 500 x 30 | keyed | 725 | 214.6 | 352.8 | 118 | 31.3 |
| 500 x 30 | streams | 732.1 | 248.8 | 389 | 169.4 | 30.6 |
| 500 x 30 | components | 752.4 | 274.4 | 423.1 | 166.6 | 32.4 |

### Arrow keys (20 presses)

| rows x cols | variant | frames sent | frames received | median ms | max ms |
| --- | --- | --- | --- | --- | --- |
| 500 x 30 | keyed | 0 | 0 | 0.2 | 0.4 |
| 500 x 30 | streams | 0 | 0 | 0.2 | 1.1 |
| 500 x 30 | components | 0 | 0 | 0.3 | 0.4 |

### LiveView process memory

| rows x cols | variant | process memory after load KB | same after GC KB | live data after GC KB | process memory after edits, sorts, pages KB | same after GC KB | live data after GC KB |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 500 x 30 | keyed | 12783 | 9373 | 6387 | 44847 | 23321 | 6388 |
| 500 x 30 | streams | 7459 | 140 | 43 | 28417 | 140 | 44 |
| 500 x 30 | components | 12784 | 11247 | 6573 | 35055 | 13496 | 6572 |
