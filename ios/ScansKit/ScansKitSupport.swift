import Metal

/// `Bundle(for:)` uchun marker klass — ScansKit `.metal` shaderlari framework
/// bundle'ida joylashadi (app'ning main bundle'ida emas).
final class ScansKitBundleToken {}

extension MTLDevice {
    /// ScansKit framework bundle'idagi `default.metallib`ni yuklaydi.
    ///
    /// nsdk kodi dastlab `device.makeDefaultLibrary()` (main bundle) ishlatgan —
    /// ScansKit framework ichida u shaderlarni topa olmaydi (nil). Shuning uchun
    /// bundle'ni aniq ko'rsatamiz.
    func scansKitDefaultLibrary() -> MTLLibrary? {
        try? makeDefaultLibrary(bundle: Bundle(for: ScansKitBundleToken.self))
    }
}
