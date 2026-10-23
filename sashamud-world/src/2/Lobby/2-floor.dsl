let
  buildFloor :: ActionManagement -> SashaLambdaDSL Object
  buildFloor lookAtKey =
    defaultObject
      & (shortName "floor" `andThen`
         description (colored White "A plain stone floor.") `andThen`
         flip objectBehavior lookAtKey)
  placeFloor :: GID Scene -> ActionManagement -> SashaLambdaDSL (GID Object)
  placeFloor lobbyGID lookAtKey = do
    floorGID <- declareObjectGID (ObjectLabel "floor")
    registerObject floorGID (buildFloor lookAtKey)
    registerObjectToScene lobbyGID floorGID (DirectionalStimulusKey floorDS)
    registerObjectToScene lobbyGID floorGID (ObjectiveKey floorOB)
    pure floorGID
in do
  lobbyGID <- declareSceneGID (SceneLabel "lobby")
  floorLookAtGID <- declareDirectionalStimulusGID lookAtF
  floorLookAtKey <- createDSATargetManagement dsaLook floorLookAtGID
  floorGID <- placeFloor lobbyGID floorLookAtKey
  linkTargetWorldOutcomeEffect (TargetKey (EntityObject floorGID)) (DirectionalStimulusActionKey floorLookAtGID) (NarrationEffect (LookAtNarration floorGID))
  finalizeGameState
