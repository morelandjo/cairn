use wasm_bindgen::prelude::*;

pub fn to_js_error<E: std::fmt::Debug>(e: E) -> JsError {
    JsError::new(&format!("{:?}", e))
}
