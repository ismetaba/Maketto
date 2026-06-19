import simd

extension SIMD4 where Scalar == Float {
    /// The first three components as a SIMD3. Used to read a column of a
    /// `simd_float4x4` transform (direction or position) on the floor plane.
    var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}
