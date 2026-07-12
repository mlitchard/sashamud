```
LOGIN
  │
  ▼
Join Channel (acJoinChan)
  │
  ▼
┌─────────────────────────────────────────────────┐
│         RHINE SIGNAL NETWORK (PlayerTick)        │
│                                                   │
│  processLeavesSF                                  │
│       │                                           │
│       ▼                                           │
│  processJoinsSF                                   │
│       │                                           │
│       ▼                                           │
│  executeJoinsSF                                   │
│       │                                           │
│       ▼                                           │
│  gatherInputSF                                    │
│       │                                           │
│       ▼                                           │
│  processInputSF                                   │
│       │                                           │
│       ▼                                           │
│  ┌────────────────────────────────────────┐       │
│  │        GAME COMPUTATION (runCommand)    │       │
│  │                                         │       │
│  │  eval                                   │       │
│  │    │                                    │       │
│  │    ▼                                    │       │
│  │  runActionProtocol                      │       │
│  │    │                                    │       │
│  │    ▼                                    │       │
│  │  processWorldOutcomes                   │       │
│  │    ├──────────────────┐                 │       │
│  │    │                  │                 │       │
│  │    ▼                  ▼                 │       │
│  │  youSeeM        processWitnesses        │       │
│  │    │                  │                 │       │
│  │    │                  ▼                 │       │
│  │    │            witnessLookM            │       │
│  │    │                  │                 │       │
│  │    └──────┬───────────┘                 │       │
│  │           │                             │       │
│  │           ▼                             │       │
│  │     NarrationMap updated                │       │
│  └────────────────────────────────────────┘       │
│       │                                           │
│       ▼                                           │
│  deliverNarrationSF                               │
│                                                   │
└─────────────────────────────────────────────────┘
        │
        ▼
  Client WS (GameNarration)
```
