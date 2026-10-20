let
  buildBall :: ActionManagement -> SashaLambdaDSL Object
  buildBall lookAtKey =
    defaultObject
      & (shortName "red ball" `andThen`
         description (colored White "a red ball that you can get and drop") `andThen`
         descriptive (DescriptiveNounPhrase red ballDS) `andThen`
         flip objectBehavior lookAtKey)
  placeBall :: GID Scene -> GID Object -> ActionManagement -> SashaLambdaDSL (GID Object)
  placeBall lobbyGID floorGID lookAtKey = do
    ballGID <- declareObjectGID (ObjectLabel "ball")
    registerObject ballGID (buildBall lookAtKey)
    registerObjectToScene lobbyGID ballGID (DirectionalStimulusKey ballDS)
    registerObjectToScene lobbyGID ballGID (ObjectiveKey ballOB)
    registerSpatial (EntityObject ballGID)  (SupportedBy (EntityObject floorGID))
    registerSpatial (EntityObject floorGID) (Supports (Data.Set.singleton (EntityObject ballGID)))
    pure ballGID
in do
  lobbyGID <- declareSceneGID (SceneLabel "lobby")
  floorGID <- declareObjectGID (ObjectLabel "floor")
  ballLookAtGID <- declareDirectionalStimulusGID lookAtF
  ballLookAtKey <- createDSATargetManagement dsaLook ballLookAtGID
  ballGID <- placeBall lobbyGID floorGID ballLookAtKey
  linkTargetWorldOutcomeEffect (TargetKey (EntityObject ballGID)) (DirectionalStimulusActionKey ballLookAtGID) (NarrationEffect (LookAtNarration ballGID))
  finalizeGameState
