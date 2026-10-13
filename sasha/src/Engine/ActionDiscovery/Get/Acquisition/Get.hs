module Engine.ActionDiscovery.Get.Acquisition.Get (manageAcquisitionProcess) where

import           Data.Functor.Identity (Identity)
import           Engine.ActionDiscovery.Instances ()
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (runActionProtocol)
  )
import           Grammar.Parser.Composites.Model (AcquisitionVerbPhrase)
import           Model.Core (AcquisitionF, Agent, GameComputation)
import           Model.GID (GID)

manageAcquisitionProcess :: GID Agent -> AcquisitionVerbPhrase -> GameComputation Identity ()
manageAcquisitionProcess = runActionProtocol @AcquisitionF
