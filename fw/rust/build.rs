use std::path::Path;

fn main() {
    let fw = Path::new(env!("CARGO_MANIFEST_DIR")).join("..");
    println!("cargo:rustc-link-arg=-T{}", fw.join("link.ld").display());
    println!("cargo:rerun-if-changed=../link.ld");
    println!("cargo:rerun-if-changed=../crt0.s");
}
