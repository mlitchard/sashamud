do
  getGID <- declareAcquisitionActionGID getF
  getKey <- createAVTargetManagement getAV getGID
  sharedBehavior getKey
  dropGID <- declareDivestmentActionGID dropF
  dropKey <- createDVManagement dropDV dropGID
  sharedBehavior dropKey
  witnessGID <- declareWitnessGID witnessF
  sharedWitnessBehavior (AcquisitionKey getAV) witnessGID
  sharedWitnessBehavior (DivestmentKey dropDV) witnessGID
  finalizeGameState
