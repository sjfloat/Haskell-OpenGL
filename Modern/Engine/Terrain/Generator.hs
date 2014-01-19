module Engine.Terrain.Generator where

import Graphics.Rendering.OpenGL.Raw (GLfloat)

import Engine.Model.Model
import Engine.Terrain.Noise

genSimplexModel :: FilePath -> FilePath ->
    GLfloat ->  -- ^ Width
    Int ->  -- ^ Octaves
    GLfloat ->  -- ^ Wavelength
    GLfloat ->  -- ^ Waveheight / intensity
    IO Model
genSimplexModel vert frag w octaves wavelength intensity = do
    -- TODO: make the last 3 args configurable.
    heights <- simplexNoise (floor w) octaves wavelength intensity
    let hCoords = heightsToCoords heights 0 1

        flat = createFlat 1 w

        vertices = applyHeights flat hCoords
        normals = calculateNormals vertices

    createModel vert frag ["position", "normal"] [vertices, normals] [3, 3]
                    (fromIntegral $ length vertices)

createFlat :: GLfloat -> GLfloat -> [GLfloat]
createFlat spacing width =
    createFlatRaw spacing width 0

    where
        createFlatRaw s w x =
            createStrip s w x 0 ++
                if x < w 
                    then createFlatRaw s w (x+1)
                else []

createStrip :: GLfloat -> GLfloat -> GLfloat -> GLfloat -> [GLfloat]
createStrip spacing len x i
    | i < len =
        [x, 0, i,
         x, 0, i+spacing,
         x+spacing, 0, i,
         x+spacing, 0, i,
         x, 0, i+spacing,
         x+spacing, 0, i+spacing] ++ createStrip spacing len x (i+spacing)
    | otherwise = []

applyHeights :: [GLfloat] -> [GLfloat] -> [GLfloat]
applyHeights (x:y:z:coords) ref =
    let foundY = findY x z ref
    in x : (if foundY == -3.1415
        then y
    else foundY) : z : applyHeights coords ref
applyHeights _ _ = []

findY :: GLfloat -> GLfloat -> [GLfloat] -> GLfloat
findY xf zf (xl:yl:zl:heights)
    | xf == xl && zf == zl = yl
    | otherwise = findY xf zf heights
findY _ _ _ = -3.1415

calculateNormals :: [GLfloat] -> [GLfloat]
calculateNormals (x1:y1:z1:x2:y2:z2:x3:y3:z3:rest) =
    let (ux, uy, uz) = (x2 - x1, y2 - y1, z2 - z1)
        (vx, vy, vz) = (x3 - x1, y3 - y1, z3 - z1)
        nx = (uy * vz) - (uz * vy)
        ny = (uz * vx) - (ux * vz)
        nz = (ux * vy) - (uy * vx)
    in repeatList 3 [nx, if ny > 0 then ny else -ny, nz] ++
            calculateNormals rest
calculateNormals _ = []

heightsToCoords :: [[GLfloat]] -> GLfloat -> GLfloat -> [GLfloat]
heightsToCoords (yi:restYs) z spacing =
    let completeLine (y:ys) x =
            [x, y, z] ++ completeLine ys (x + spacing)
        completeLine [] _ = []
    in completeLine yi 0 ++ heightsToCoords restYs (z + spacing) spacing
heightsToCoords [] _ _ = []

repeatList :: Int -> [a] -> [a]
repeatList i arr = concat $ replicate i arr