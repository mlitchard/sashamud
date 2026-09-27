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
          (ImportList ["lookAtF", "lookF", "witnessF"])
      , ModuleImport "Data.Set" (QualifiedAs Nothing)
          (ImportList ["singleton"])
      , ModuleImport "DSL.Model.EDSL.SashaLambdaDSL" NotQualified
          (ImportList
            [ "SashaLambdaDSL"
            , "createDSAManagement"
            , "createISAManagement"
            , "declareDirectionalStimulusGID"
            , "declareImplicitStimulusGID"
            , "declareObjectGID"
            , "declareSceneGID"
            , "declareWitnessGID"
            , "description"
            , "finalizeGameState"
            , "linkWorldOutcomeEffect"
            , "newUser"
            , "objectBehavior"
            , "playerBehavior"
            , "registerObject"
            , "registerObjectToScene"
            , "registerScene"
            , "registerSpatial"
            , "sceneBehavior"
            , "sceneDescriptionRich"
            , "shortName"
            , "title"
            , "witnessBehavior"
            ])
      , ModuleImport "DSL.Vocabulary" NotQualified
          (ImportList ["andThen"])
      , ModuleImport "Grammar.Parser.Atomics.Semantics.Verbs.DirectionalStimulus" NotQualified
          (ImportList ["dsaLook"])
      , ModuleImport "Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus" NotQualified
          (ImportList ["isaLook"])
      , ModuleImport "Grammar.Parser.GCase" NotQualified
          (ImportList ["VerbKey (DirectionalStimulusKey, ImplicitStimulusKey)"])
      , ModuleImport "Model.Core" NotQualified
          (ImportList
            [ "ActionEffectKey (DirectionalStimulusActionKey, ImplicitStimulusActionKey)"
            , "ActionManagement"
            , "ActionManagementFunctions (ActionManagementFunctions)"
            , "Agent (Agent, _agentActionManagement, _agentDescription, _agentKind, _agentShortName, _agentTitle, _agentWitnessManagement)"
            , "AgentKind (Denizen)"
            , "EntityID (EntityObject)"
            , "GameState"
            , "NarrationComputation (LookAtNarration, LookNarration)"
            , "Object"
            , "Scene"
            , "SpatialRelationship (SupportedBy, Supports)"
            , "WorldOutcome (NarrationEffect)"
            , "defaultObject"
            , "defaultScene"
            ])
      , ModuleImport "Model.RichText" NotQualified
          (ImportList ["TextColor (White)", "colored", "plain"])
      ]
