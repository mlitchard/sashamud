do
  getGID <- declareAcquisitionActionGID getF
  getKey <- createAVTargetManagement getAV getGID
  sharedBehavior AgentEntity getKey
  dropGID <- declareDivestmentActionGID dropF
  dropKey <- createDVManagement dropDV dropGID
  sharedBehavior AgentEntity dropKey
  witnessGID <- declareWitnessGID witnessF
  sharedWitnessBehavior AgentEntity witnessGID
  finalizeGameState
