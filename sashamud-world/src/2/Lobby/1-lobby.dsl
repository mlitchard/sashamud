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
    , _agentKind              = Denizen
    }
  playerTemplate :: ActionManagement -> ActionManagement -> SashaLambdaDSL (Text -> Agent)
  playerTemplate lookKey lookAtKey = do
    denizen  <- playerBehavior defaultDenizen lookKey
    playerBehavior denizen lookAtKey
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
  sceneLookGID <- declareImplicitStimulusGID lookF
  sceneLookKey <- createISATargetManagement isaLook sceneLookGID
  (_, playerLookKey)           <- declareLook
  sceneLookAtGID <- declareDirectionalStimulusGID lookAtF
  sceneLookAtKey <- createDSATargetManagement dsaLook sceneLookAtGID
  (_, playerLookAtKey)         <- declareLookAt
  agentLookAtGID <- declareDirectionalStimulusGID lookAtF
  agentLookAtKey <- createDSATargetManagement dsaLook agentLookAtGID
  sharedBehavior AgentEntity agentLookAtKey
  witnessGID <- declareWitnessGID witnessF
  sharedWitnessBehavior AgentEntity witnessGID
  registerScene lobbyGID (buildLobby sceneLookKey sceneLookAtKey)
  template <- playerTemplate playerLookKey playerLookAtKey
  newUser lobbyGID template
  linkTargetWorldOutcomeEffect (TargetKey (EntityScene lobbyGID)) (ImplicitStimulusActionKey sceneLookGID) (NarrationEffect LookNarration)
  linkWorldOutcomeEffect AgentEntity (DirectionalStimulusActionKey agentLookAtGID) (NarrationEffect LookAtAgentNarration)
  finalizeGameState
