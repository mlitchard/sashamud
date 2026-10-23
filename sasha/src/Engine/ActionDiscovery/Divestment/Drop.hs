module Engine.ActionDiscovery.Divestment.Drop (manageDivestmentProcess) where

import           Data.Functor.Identity (Identity)
import           Engine.ActionDiscovery.Instances ()
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (runActionProtocol)
  )
import           Grammar.Parser.Composites.Model (DivestmentVerbPhrase)
import           Model.Core (Agent, DivestmentF, GameComputation)
import           Model.GID (GID)

manageDivestmentProcess :: GID Agent -> DivestmentVerbPhrase -> GameComputation Identity ()
manageDivestmentProcess = runActionProtocol @DivestmentF
