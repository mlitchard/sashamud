module ReifySpec (spec) where

import           Data.List (unlines)
import           SashaPrelude (Either (Left, Right), String, pure, show, ($))

import           DSL.Reify (reifyDSL)
import           Language.Haskell.Interpreter (InterpreterError (WontCompile))
import           Test.Hspec (Spec, describe, expectationFailure, it)

spec :: Spec
spec = describe "reifyDSL" $ do
    it "reifies the sashaMudWorld source" $ do
        result <- reifyDSL worldSource
        case result of
            Right _  -> pure ()
            Left err -> expectationFailure (show err)
    it "rejects a submission of the wrong type" $ do
        result <- reifyDSL "declareSceneGID"
        case result of
            Left (WontCompile _) -> pure ()
            Left err             -> expectationFailure (show err)
            Right _              -> expectationFailure "expected WontCompile"
    it "rejects a module that is not imported" $ do
        result <- reifyDSL "System.IO.Unsafe.unsafePerformIO"
        case result of
            Left (WontCompile _) -> pure ()
            Left err             -> expectationFailure (show err)
            Right _              -> expectationFailure "expected WontCompile"

worldSource :: String
worldSource = unlines
    [ "let"
    , "  buildLobby :: ActionManagement -> ActionManagement -> SashaLambdaDSL Scene"
    , "  buildLobby sceneLookKey sceneLookAtKey ="
    , "    defaultScene"
    , "      & (title \"the lobby\" `andThen`"
    , "         sceneDescriptionRich (colored White \"A spacious lobby with high ceilings.\") `andThen`"
    , "         flip sceneBehavior sceneLookKey `andThen`"
    , "         flip sceneBehavior sceneLookAtKey)"
    , ""
    , "  buildFloor :: ActionManagement -> SashaLambdaDSL Object"
    , "  buildFloor lookAtKey ="
    , "    defaultObject"
    , "      & (shortName \"floor\" `andThen`"
    , "         description (colored White \"A plain stone floor.\") `andThen`"
    , "         flip objectBehavior lookAtKey)"
    , ""
    , "  buildBall :: ActionManagement -> SashaLambdaDSL Object"
    , "  buildBall lookAtKey ="
    , "    defaultObject"
    , "      & (shortName \"ball\" `andThen`"
    , "         description (colored White \"A small red ball.\") `andThen`"
    , "         flip objectBehavior lookAtKey)"
    , ""
    , "  defaultDenizen :: Text -> Agent"
    , "  defaultDenizen playerName = Agent"
    , "    { _agentShortName         = plain playerName"
    , "    , _agentDescription       = colored White \"A player.\""
    , "    , _agentTitle             = mempty"
    , "    , _agentActionManagement  = ActionManagementFunctions mempty"
    , "    , _agentWitnessManagement = mempty"
    , "    , _agentKind              = Denizen"
    , "    }"
    , "in do"
    , "  lobbyGID      <- declareSceneGID \"lobby\""
    , ""
    , "  sceneLookGID  <- declareImplicitStimulusGID lookF"
    , "  playerLookGID <- declareImplicitStimulusGID lookF"
    , "  sceneLookKey  <- createISAManagement isaLook sceneLookGID"
    , "  playerLookKey <- createISAManagement isaLook playerLookGID"
    , ""
    , "  sceneLookAtGID  <- declareDirectionalStimulusGID lookAtF"
    , "  playerLookAtGID <- declareDirectionalStimulusGID lookAtF"
    , "  floorLookAtGID  <- declareDirectionalStimulusGID lookAtF"
    , "  ballLookAtGID   <- declareDirectionalStimulusGID lookAtF"
    , "  sceneLookAtKey  <- createDSAManagement dsaLook sceneLookAtGID"
    , "  playerLookAtKey <- createDSAManagement dsaLook playerLookAtGID"
    , "  floorLookAtKey  <- createDSAManagement dsaLook floorLookAtGID"
    , "  ballLookAtKey   <- createDSAManagement dsaLook ballLookAtGID"
    , ""
    , "  witnessGID <- declareWitnessGID witnessF"
    , ""
    , "  floorGID <- declareObjectGID"
    , "  ballGID  <- declareObjectGID"
    , ""
    , "  registerObject floorGID (buildFloor floorLookAtKey)"
    , "  registerObject ballGID  (buildBall ballLookAtKey)"
    , ""
    , "  registerObjectToScene lobbyGID floorGID \"FLOOR\""
    , "  registerObjectToScene lobbyGID ballGID  \"BALL\""
    , ""
    , "  registerSpatial (EntityObject ballGID)  (SupportedBy (EntityObject floorGID))"
    , "  registerSpatial (EntityObject floorGID) (Supports (Data.Set.singleton (EntityObject ballGID)))"
    , ""
    , "  registerScene lobbyGID (buildLobby sceneLookKey sceneLookAtKey)"
    , ""
    , "  denizen       <- playerBehavior defaultDenizen playerLookKey"
    , "  denizen'      <- playerBehavior denizen playerLookAtKey"
    , "  w1            <- witnessBehavior denizen' (ImplicitStimulusKey isaLook) witnessGID"
    , "  w2            <- witnessBehavior w1 (DirectionalStimulusKey dsaLook) witnessGID"
    , "  newUser lobbyGID w2"
    , ""
    , "  linkWorldOutcomeEffect (ImplicitStimulusActionKey sceneLookGID) (NarrationEffect LookNarration)"
    , "  linkWorldOutcomeEffect (DirectionalStimulusActionKey ballLookAtGID) (NarrationEffect (LookAtNarration ballGID))"
    , "  linkWorldOutcomeEffect (DirectionalStimulusActionKey floorLookAtGID) (NarrationEffect (LookAtNarration floorGID))"
    , "  finalizeGameState"
    ]
