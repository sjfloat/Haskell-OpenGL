module TestVals where

import Control.Applicative ((<$>), (<*>))
import System.FilePath ((</>))
import Data.IORef (IORef, newIORef)

import Engine.Object.Player
import Engine.Model.ModelLoader
import Engine.Terrain.Generator
import Engine.Core.Vec
import Engine.Core.World
import Engine.Object.GameObject
import Engine.Model.Model

mkWorld :: IO World
mkWorld = do
    obj1 <- mkObj >>= newIORef
    obj2 <- mkObj2 >>= newIORef
    World
        <$> newIORef mkPlayer
        <*> return [obj1, obj2]
        <*> return [("lightPos", [2.0, 2.0, 0.0])]
        <*> mkWorldStateRef

mkWorldState :: WorldState
mkWorldState = WorldState 0

mkWorldStateRef :: IO (IORef WorldState)
mkWorldStateRef = newIORef mkWorldState

mkObj :: IO GameObject
mkObj =
    Entity (Vec3 3 1 0) <$> mkModel

mkObj2 :: IO GameObject
mkObj2 =
    Entity (Vec3 0 0 0) <$> mkTerrain

mkModel :: IO Model
mkModel = do
    worldStateRef <- mkWorldStateRef
    loadObjModel worldStateRef ("res" </> "objects/wow/wow.obj")
                               ("shaders" </> "min.vert")
                               ("shaders" </> "min.frag")

mkTerrain :: IO Model
mkTerrain = genModel
            "shaders/max.vert"
            "shaders/max.frag"
            50

mkModel3 :: IO Model
mkModel3 = do
    worldStateRef <- mkWorldStateRef
    loadObjModel worldStateRef ("res" </> "objects/ibanez/ibanez.obj")
                               ("shaders" </> "min.vert")
                               ("shaders" </> "min.frag")

