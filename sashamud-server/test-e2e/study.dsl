do
  studyGID <- declareSceneGID (SceneLabel "study")
  tableGID <- declareObjectGID (ObjectLabel "table")
  cupGID   <- declareObjectGID (ObjectLabel "cup")
  registerObject tableGID (defaultObject & shortName "table")
  registerObject cupGID   (defaultObject & shortName "cup")
  registerObjectToScene studyGID tableGID (DirectionalStimulusKey tableDS)
  registerObjectToScene studyGID tableGID (ObjectiveKey tableOB)
  registerObjectToScene studyGID cupGID (DirectionalStimulusKey cupDS)
  registerObjectToScene studyGID cupGID (ObjectiveKey cupOB)
  registerSpatial (EntityObject cupGID)   (SupportedBy (EntityObject tableGID))
  registerSpatial (EntityObject tableGID) (Supports (Data.Set.singleton (EntityObject cupGID)))
  registerScene studyGID (defaultScene & title "the study")
  finalizeGameState
