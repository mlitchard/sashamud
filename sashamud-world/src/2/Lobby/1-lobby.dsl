let
  buildLobby :: ActionManagement -> ActionManagement -> SashaLambdaDSL Scene
  buildLobby sceneLookKey sceneLookAtKey =
    defaultScene
      & (title "the lobby" `andThen`
         sceneDescriptionRich (colored White "A spacious lobby with high ceilings.") `andThen`
         flip sceneBehavior sceneLookKey `andThen`
         flip sceneBehavior sceneLookAtKey)
  defaultDenizen :: Text -> Agent
  defaultDenizen playerName = Agent
    { _agentShortName         = plain playerName
    , _agentDescription       = colored White "A player."
    , _agentTitle             = mempty
    , _agentActionManagement  = ActionManagementFunctions mempty
    , _agentWitnessManagement = mempty
    , _agentKind              = Denizen
    }
  playerTemplate :: ActionManagement -> ActionManagement -> GID WitnessF -> SashaLambdaDSL (Text -> Agent)
  playerTemplate lookKey lookAtKey witnessGID = do
    denizen  <- playerBehavior defaultDenizen lookKey
    denizen' <- playerBehavior denizen lookAtKey
    w1       <- witnessBehavior denizen' (ImplicitStimulusKey isaLook) witnessGID
    witnessBehavior w1 (DirectionalStimulusKey dsaLook) witnessGID
  declareLook :: SashaLambdaDSL (GID ImplicitStimulusF, ActionManagement)
  declareLook = do
    gid <- declareImplicitStimulusGID lookF
    key <- createISAManagement isaLook gid
    pure (gid, key)
  declareLookAt :: SashaLambdaDSL (GID DirectionalStimulusF, ActionManagement)
  declareLookAt = do
    gid <- declareDirectionalStimulusGID lookAtF
    key <- createDSAManagement dsaLook gid
    pure (gid, key)
in do
  lobbyGID <- declareSceneGID (SceneLabel "lobby")
  (sceneLookGID, sceneLookKey) <- declareLook
  (_, playerLookKey)           <- declareLook
  (_, sceneLookAtKey)          <- declareLookAt
  (_, playerLookAtKey)         <- declareLookAt
  witnessGID <- declareWitnessGID witnessF
  registerScene lobbyGID (buildLobby sceneLookKey sceneLookAtKey)
  template <- playerTemplate playerLookKey playerLookAtKey witnessGID
  newUser lobbyGID template
  linkWorldOutcomeEffect (ImplicitStimulusActionKey sceneLookGID) (NarrationEffect LookNarration)
  finalizeGameState
