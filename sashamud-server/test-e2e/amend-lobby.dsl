do
  modifyScene (SceneLabel "lobby") (sceneDescriptionRich (colored White "A spacious lobby with a freshly polished floor."))
  modifyObject (ObjectLabel "ball") (description (colored White "A small blue ball."))
  finalizeGameState
