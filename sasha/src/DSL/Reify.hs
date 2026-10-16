module DSL.Reify
  ( reifyDSL
  ) where

import           SashaPrelude

import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL)
import           Language.Haskell.Interpreter
  ( Extension (OverloadedStrings)
  , ImportList (ImportList, NoImportList)
  , InterpreterError (UnknownError)
  , ModuleImport (ModuleImport)
  , ModuleQualification (NotQualified, QualifiedAs)
  , OptionVal ((:=))
  , as
  , installedModulesInScope
  , interpret
  , languageExtensions
  , reset
  , set
  , setImportsF
  )
import           Language.Haskell.Interpreter.Unsafe
  ( unsafeRunInterpreterWithArgsLibdir
  )
import           Model.Core (GameState)
import           System.Environment (lookupEnv)

reifyDSL :: String -> IO (Either InterpreterError (SashaLambdaDSL GameState))
reifyDSL source = do
  mLibDir    <- lookupEnv "HINT_GHC_LIB_DIR"
  mPackageDb <- lookupEnv "HINT_GHC_PACKAGE_PATH"
  case (mLibDir, mPackageDb) of
    (Just libDir, Just packageDb) ->
      unsafeRunInterpreterWithArgsLibdir
        ["-package-db=" <> packageDb, "-package-env", "-"]
        libDir
        do
          reset
          set [installedModulesInScope := False, languageExtensions := [OverloadedStrings]]
          setImportsF dslImports
          interpret source (as :: SashaLambdaDSL GameState)
    (Nothing, _) -> pure (Left (UnknownError "HINT_GHC_LIB_DIR is not set"))
    (_, Nothing) -> pure (Left (UnknownError "HINT_GHC_PACKAGE_PATH is not set"))
  where
    dslImports :: [ModuleImport]
    dslImports =
      [ ModuleImport "SashaPrelude" NotQualified NoImportList
      , ModuleImport "ConstraintRefinement.Actions" NotQualified
          (ImportList ["dropDeniedF", "dropF", "getDeniedF", "getF", "lookAtDeniedF", "lookAtF", "lookDeniedF", "lookF", "witnessF"])
      , ModuleImport "Data.Set" (QualifiedAs Nothing)
          (ImportList ["singleton"])
      , ModuleImport "DSL.Model.EDSL.SashaLambdaDSL" NotQualified
          (ImportList
            [ "SashaLambdaDSL"
            , "createAVSupportManagement"
            , "createAVTargetManagement"
            , "createDSAManagement"
            , "createDVManagement"
            , "createDVSurfaceManagement"
            , "createISAManagement"
            , "declareAcquisitionActionGID"
            , "declareDirectionalStimulusGID"
            , "declareDivestmentActionGID"
            , "declareImplicitStimulusGID"
            , "declareObjectGID"
            , "declareSceneGID"
            , "declareWitnessGID"
            , "description"
            , "descriptive"
            , "finalizeGameState"
            , "linkEntityActionEffect"
            , "linkWorldOutcomeEffect"
            , "modifyNewUserAgent"
            , "modifyObject"
            , "modifyScene"
            , "newUser"
            , "objectBehavior"
            , "playerBehavior"
            , "registerObject"
            , "registerObjectToScene"
            , "registerScene"
            , "registerSpatial"
            , "sceneBehavior"
            , "sceneDescriptionRich"
            , "sharedBehavior"
            , "sharedWitnessBehavior"
            , "shortName"
            , "title"
            , "witnessBehavior"
            ])
      , ModuleImport "DSL.Vocabulary" NotQualified
          (ImportList ["andThen"])
      , ModuleImport "Grammar.Parser.Atomics.Semantics.Adjectives" NotQualified
          (ImportList ["red"])
      , ModuleImport "Grammar.Parser.Atomics.Semantics.Nouns.DirectionalStimulus" NotQualified
          (ImportList ["ballDS"])
      , ModuleImport "Grammar.Parser.Atomics.Semantics.Verbs.Acquisition" NotQualified
          (ImportList ["getAV"])
      , ModuleImport "Grammar.Parser.Atomics.Semantics.Verbs.DirectionalStimulus" NotQualified
          (ImportList ["dsaLook"])
      , ModuleImport "Grammar.Parser.Atomics.Semantics.Verbs.Divestment" NotQualified
          (ImportList ["dropDV"])
      , ModuleImport "Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus" NotQualified
          (ImportList ["isaLook"])
      , ModuleImport "Grammar.Parser.Composites.Nouns" NotQualified
          (ImportList ["NounPhrase (DescriptiveNounPhrase)"])
      , ModuleImport "Grammar.Parser.GCase" NotQualified
          (ImportList ["VerbKey (AcquisitionKey, DirectionalStimulusKey, DivestmentKey, ImplicitStimulusKey)"])
      , ModuleImport "Model.Core" NotQualified
          (ImportList
            [ "ActionEffectKey (AcquisitionalActionKey, DirectionalStimulusActionKey, DivestmentActionKey, ImplicitStimulusActionKey)"
            , "ActionManagement"
            , "ActionManagementFunctions (ActionManagementFunctions)"
            , "ActionManagementOperation (AddAcquisitionVerb, AddDivestmentVerb)"
            , "Agent (Agent, _agentActionManagement, _agentDescription, _agentKind, _agentShortName, _agentTitle, _agentWitnessManagement)"
            , "AgentKind (Denizen)"
            , "DirectionalStimulusF"
            , "DivestmentTargetType (DivestToSurface')"
            , "EntityID (EntityObject)"
            , "EntityKey (ActingAgentKey, AgentKey', ObjectKey', SceneKey')"
            , "GameState"
            , "ImplicitStimulusF"
            , "NarrationComputation (LookAtNarration, LookNarration, StaticNarration)"
            , "Object"
            , "ObjectLabel (ObjectLabel)"
            , "Scene"
            , "SceneLabel (SceneLabel)"
            , "SpatialRelationship (Inventory, SupportedBy, Supports)"
            , "SpatialRelationshipComputation (Acquisition, Divestiture)"
            , "WitnessF"
            , "WorldOutcome (NarrationEffect, SpatialRelationshipEffect)"
            , "defaultObject"
            , "defaultScene"
            ])
      , ModuleImport "Model.GID" NotQualified (ImportList ["GID"])
      , ModuleImport "Model.RichText" NotQualified
          (ImportList ["TextColor (White)", "colored", "plain"])
      ]
