module Engine.Model.ObjLoader where

import System.IO
    (openFile, IOMode(..), hGetContents, hClose)
import Data.List (isPrefixOf)
import Data.List.Split (splitOn)
import Data.Maybe (isJust, fromJust)
import Control.Monad (liftM)

import qualified Data.Vector.Storable as V
import qualified Data.DList as D

import Graphics.Rendering.OpenGL.Raw (GLfloat)

import Engine.Model.Material
    (Material(..), emptyMaterial, loadMtlFile)
import Engine.Model.Model
    (Model(..), createModel)
import Engine.Core.Vec (Vec3(..))

loadObjModel ::
    FilePath ->
    FilePath ->
    FilePath ->
    IO Model
loadObjModel objFile vert frag =
    let attrNames = ["position", "texCoord", "normal", "color", "textureId"]
    in do
    fileContents <- openFile objFile ReadMode >>= hGetContents
    (mats, lib) <- loadObjMaterials $ lines fileContents
    let obj = loadObj fileContents

        dat = toArrays obj
        materialDiffs = fromVec3M $ map matDiffuseColor mats
        materialTexIds = map (fromIntegral . fromJustSafe . matTexId) mats

        totalData = dat ++ [materialDiffs, materialTexIds]

    tmp <- createModel vert frag
        attrNames
        totalData
        [3, 2, 3, 3, 1]
        (fromIntegral (length $ head dat) `div` 3)

    let mTexIds = map (fromJust . matTexId) $ filter (isJust . matTexId) lib
        mTextures = map (fromJust . matTexture) $ filter (isJust . matTexture) lib
    return tmp{modelTextures =
        zip mTextures
            mTexIds}

-- | Parse an .obj file and return a Vec3 [GLfloat]
--   containing the vertices, texture coordinates,
--   and normals, in that order.
loadObjFile :: FilePath -> IO (Vec3 [GLfloat])
loadObjFile file = do
    handle <- openFile file ReadMode
    objData <- liftM loadObj $! hGetContents handle
    hClose handle
    return objData

-- | Parse a string containing the specification
--   for an .obj model and return a Vec3 [GLfloat]
--   containing the vertices, texture coordinates,
--   and normals, in that order.
loadObj :: String -> Vec3 [GLfloat]
loadObj text =
    let verts = parseVertices text
        norms = parseNormals text
        texs = parseTextures text
        faces = parseFaces text
    in packObj verts norms texs faces

-- | Given DLists containg raw information read from a
--   .obj file, put together a Vec3 [GLfloat] of the
--   vertices, texture coordinates, and normals,
--   in that order, formatted to be sent to OpenGL.
packObj ::
    D.DList GLfloat ->      -- ^ Vertices
    D.DList GLfloat ->      -- ^ Normals
    D.DList GLfloat ->      -- ^ Texture coords
    D.DList (Maybe Int) ->  -- ^ Face Definitions
    Vec3 [GLfloat]
packObj verts norms texs faces =
    let lFaces = D.toList faces
        lVerts = V.fromList $ D.toList verts
        lNorms = V.fromList $ D.toList norms
        lTexs = V.fromList $ D.toList texs

        faceVerts = takeEvery3 1 lFaces
        faceTexs = takeEvery3 2 lFaces
        faceNorms = takeEvery3 3 lFaces

        realVerts = D.toList $ getIndicesD lVerts faceVerts 3
        realNorms = D.toList $ getIndicesD lNorms faceNorms 3
        realTexs = D.toList $ getIndicesD lTexs faceTexs 2
    in Vec3 realVerts realTexs realNorms

-- | Given a List of () indices to read and the
--   Vector to read from, read given indices for all
--   Just values, and use -1.0 as a default value for
--   Nothings. Returns a DList of GLfloats.
getIndicesD :: V.Vector GLfloat -> [Maybe Int] -> Int -> D.DList GLfloat
getIndicesD haystack (x:xs) vecType
    | isJust x =
            -- Get the section of the vector that is needed.
        let index = vecType * (fromJust x - 1)
            splitList = snd $ V.splitAt index haystack
            -- Switch to dlist for its O(1) appending.
            ret = D.fromList $ V.toList $ V.take vecType splitList
        in ret `D.append` getIndicesD haystack xs vecType
    | otherwise = D.replicate vecType (-1.0) `D.append` getIndicesD haystack xs vecType
getIndicesD _ _ _ = D.empty

takeEvery3 :: Int -> [a] -> [a]
takeEvery3 offset (x:y:z:rest)
    | offset == 1 = x : takeEvery3 offset rest
    | offset == 2 = y : takeEvery3 offset rest
    | offset == 3 = z : takeEvery3 offset rest
    | otherwise = error $ "ObjLoader.takeEvery 3: arg"
                        ++ "must be 1, 2, or 3"
takeEvery3 _ _ = []

parseFaces :: String -> D.DList (Maybe Int)
parseFaces = D.concat . map faceLineCheck . lines
    where
    faceLineCheck line =
        if "f " `isPrefixOf` line
            then parseFaceLine line
        else D.empty

{-# INLINE parseFaceLine #-}
parseFaceLine :: String -> D.DList (Maybe Int)
parseFaceLine =
    D.concat . map parseFaceGroup . tail . words

{-# INLINE parseFaceGroup #-}
parseFaceGroup :: String -> D.DList (Maybe Int)
parseFaceGroup =
    D.fromList . map retrieveData . splitOn "/"
    where
    retrieveData text =
        if null text
            then Nothing
        else Just $ read text

parseVertices :: String -> D.DList GLfloat
parseVertices = parsePrefix "v "
parseNormals :: String -> D.DList GLfloat
parseNormals = parsePrefix "vn "
parseTextures :: String -> D.DList GLfloat
parseTextures =
    D.concat . map lineCheck . lines
    where
    lineCheck line =
        if "vt " `isPrefixOf` line
            then
                let [x, y] = D.toList $ parseLine line
                in D.fromList [x, 1-y]
        else D.empty

-- | Call parseLine on all lines with the given prefix
--   in given String.
parsePrefix :: Read a => String -> String -> D.DList a
parsePrefix prefix =
    D.concat . map lineCheck . lines
    where
    {-# INLINE lineCheck #-}
    lineCheck line =
        if prefix `isPrefixOf` line
            then parseLine line
        else D.empty

{-# INLINE parseLine #-}
parseLine :: Read a => String -> D.DList a
parseLine = D.map read . D.tail . D.fromList . words

loadObjMaterials :: [String] -> IO ([Material], [Material])
loadObjMaterials contents = do
    --library <- loadObjMaterialLib handle1
    library <- loadObjMaterialLib contents

    let listRet = listOfMats contents library emptyMaterial
    return (listRet, library)

loadObjMaterialLib :: [String] -> IO [Material]
loadObjMaterialLib (line:rest) =
    if "mtllib " `isPrefixOf` line
        then do
            mtl <- loadMtlFile . last . words $ line
            others <- loadObjMaterialLib rest
            return $ mtl ++ others
    else loadObjMaterialLib rest
loadObjMaterialLib _ = return []

listOfMats :: [String] -> [Material] -> Material -> [Material]
listOfMats (line:rest) library currentMat
    | "usemtl " `isPrefixOf` line =
        let mat = findMaterial (last . words $ line) library
        in listOfMats rest library mat
    | "f " `isPrefixOf` line =
        replicate 3 currentMat ++
            listOfMats rest library currentMat
    | otherwise = listOfMats rest library currentMat
listOfMats _ _ _ = []

{-# INLINE findMaterial #-}
findMaterial :: String -> [Material] -> Material
findMaterial name library = head $ filter (\x -> matName x == name) library

toArrays :: Vec3 [a] -> [[a]]
toArrays (Vec3 x y z) = [x, y, z]

fromVec3M :: [Maybe (Vec3 a)] -> [a]
fromVec3M (Just (Vec3 x y z) : xs) =
    [x, y, z] ++ fromVec3M xs
fromVec3M [] = []
fromVec3M (Nothing : _) = error "fromVec3M: argument contained Nothing."

{-# INLINE fromJustSafe #-}
fromJustSafe :: Num a => Maybe a -> a
fromJustSafe (Just x) = x
fromJustSafe Nothing = 0