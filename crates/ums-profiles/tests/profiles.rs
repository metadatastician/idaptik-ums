use serde_json::Value;
use std::fs;
use std::path::{Path, PathBuf};
use ums_profiles::{compile_idaptik, read_and_validate_declared_profile};

fn root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../..")
        .canonicalize()
        .expect("workspace root")
}

#[test]
fn slavia_border_path_validates_through_the_generic_profile_protocol() {
    let root = root();
    read_and_validate_declared_profile(
        &root.join("profiles/slavia/v1/profile.json"),
        &root.join("profiles/slavia/v1/fixtures/zone-a-border-path.json"),
    )
    .expect("bounded Slavia fixture validates");
}

#[test]
fn slavia_vocabulary_does_not_leak_into_ums_rust_core() {
    let root = root();
    let profile: Value = serde_json::from_str(
        &fs::read_to_string(root.join("profiles/slavia/v1/profile.json")).expect("profile"),
    )
    .expect("profile json");
    let terms = profile["vocabulary"].as_array().expect("vocabulary");
    for source in [
        root.join("crates/ums-ai-edit/src"),
        root.join("crates/ums-dlc/src"),
    ] {
        for entry in fs::read_dir(source).expect("source directory") {
            let path = entry.expect("source entry").path();
            if path.extension().and_then(|ext| ext.to_str()) != Some("rs") {
                continue;
            }
            let text = fs::read_to_string(&path).expect("source file");
            for term in terms {
                let term = term.as_str().expect("term");
                assert!(
                    !text.contains(term),
                    "{} leaked Slavia vocabulary `{term}`",
                    path.display()
                );
            }
        }
    }
}

#[test]
fn idaptik_compiler_consumes_the_sibling_game_contract() {
    let Some(idaptik_root) = root().parent().map(|meta| meta.join("IDApTIK")) else {
        panic!("UMS must have a meta-repos parent");
    };
    let package = compile_idaptik(
        &root().join("profiles/idaptik/v1/ghost-lobby.ums.json"),
        &idaptik_root,
    )
    .expect("compile against game contract");
    assert_eq!(package["format"], "idaptik-package/v1");
    assert_eq!(package["scenario"]["scenario_id"], package["scenario_id"]);
    assert_eq!(package["contract"]["version"], "1.0.0");
}
