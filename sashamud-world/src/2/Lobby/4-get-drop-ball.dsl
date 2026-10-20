do
  sceneGetGID <- declareAcquisitionActionGID getF
  sceneGetKey <- createAVTargetManagement getAV sceneGetGID
  sceneDropGID <- declareDivestmentActionGID dropF
  sceneDropKey <- createDVManagement dropDV sceneDropGID
  modifyScene (SceneLabel "lobby") (flip sceneBehavior sceneGetKey `andThen` flip sceneBehavior sceneDropKey)
  floorGetGID <- declareAcquisitionActionGID getF
  floorGetKey <- createAVSupportManagement getAV floorGetGID
  floorDropGID <- declareDivestmentActionGID dropF
  floorDropKey <- createDVSurfaceManagement dropDV floorDropGID
  modifyObject (ObjectLabel "floor") (flip objectBehavior floorGetKey `andThen` flip objectBehavior floorDropKey)
  ballGetGID <- declareAcquisitionActionGID getF
  ballGetKey <- createAVTargetManagement getAV ballGetGID
  ballDropGID <- declareDivestmentActionGID dropF
  ballDropKey <- createDVManagement dropDV ballDropGID
  modifyObject (ObjectLabel "ball") (flip objectBehavior ballGetKey `andThen` flip objectBehavior ballDropKey)
  ballGID <- declareObjectGID (ObjectLabel "ball")
  linkTargetWorldOutcomeEffect (TargetKey (EntityObject ballGID)) (AcquisitionalActionKey ballGetGID) (NarrationEffect (StaticNarration "You pick up the red ball."))
  linkTargetWorldOutcomeEffect (TargetKey (EntityObject ballGID)) (DivestmentActionKey ballDropGID) (NarrationEffect (StaticNarration "You drop the red ball."))
  finalizeGameState
