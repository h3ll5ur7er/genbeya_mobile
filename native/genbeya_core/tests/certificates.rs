//! Adding CA certificates from memory, as the app does on Android.

use genbeya_core::git::add_ca_certificates;

/// A small standard Base64 decoder, so the test needs no extra crate.
fn base64(text: &str) -> Vec<u8> {
    let value = |c: u8| match c {
        b'A'..=b'Z' => Some(c - b'A'),
        b'a'..=b'z' => Some(c - b'a' + 26),
        b'0'..=b'9' => Some(c - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    };
    let (mut out, mut buffer, mut bits) = (Vec::new(), 0u32, 0);
    for v in text.bytes().filter_map(value) {
        buffer = (buffer << 6) | u32::from(v);
        bits += 6;
        if bits >= 8 {
            bits -= 8;
            out.push((buffer >> bits) as u8);
        }
    }
    out
}

fn system_certificates() -> Vec<Vec<u8>> {
    let pem = std::fs::read_to_string("/etc/ssl/certs/ca-certificates.crt").expect("a CA bundle on this machine");
    pem.split("-----BEGIN CERTIFICATE-----")
        .skip(1)
        .filter_map(|block| block.split("-----END CERTIFICATE-----").next())
        .map(base64)
        .collect()
}

#[test]
fn adds_every_certificate_and_skips_what_is_not_one() {
    let mut certificates = system_certificates();
    let real = certificates.len() as u32;
    assert!(real > 50, "expected the machine's CA certificates, found {real}");
    certificates.push(b"not a certificate".to_vec());
    certificates.push(Vec::new());
    assert_eq!(add_ca_certificates(&certificates).unwrap(), real);
    // Adding the same certificates again is harmless.
    assert_eq!(add_ca_certificates(&certificates[..3]).unwrap(), 3);
}

/// A real HTTPS clone trusting only certificates added from memory, as on
/// Android. Run with OpenSSL's own locations pointing nowhere:
/// `SSL_CERT_FILE=/nonexistent SSL_CERT_DIR=/nonexistent GENBEYA_TEST_CA_PEM=<bundle> cargo test -- --ignored`.
/// With GENBEYA_TEST_SKIP_ADD set, it checks the opposite: no certificate, no clone.
#[test]
#[ignore]
fn https_clone_trusting_certificates_from_memory() {
    use genbeya_core::git::{clone, Auth, RemoteOptions};
    let bundle = std::env::var("GENBEYA_TEST_CA_PEM").expect("GENBEYA_TEST_CA_PEM names a PEM bundle");
    let url = std::env::var("GENBEYA_TEST_URL").unwrap_or_else(|_| "https://github.com/h3ll5ur7er/genbeya_mobile.git".into());
    let skip = std::env::var("GENBEYA_TEST_SKIP_ADD").is_ok();
    if !skip {
        let pem = std::fs::read_to_string(bundle).unwrap();
        let ders: Vec<Vec<u8>> = pem
            .split("-----BEGIN CERTIFICATE-----")
            .skip(1)
            .filter_map(|block| block.split("-----END CERTIFICATE-----").next())
            .map(base64)
            .collect();
        println!("added {} certificates", add_ca_certificates(&ders).unwrap());
    }
    let tmp = tempfile::tempdir().unwrap();
    let options = RemoteOptions { auth: Auth::None, trusted_host_keys: vec![] };
    let result = clone(&url, &tmp.path().join("clone"), None, Some(1), &options, None, None);
    if skip {
        let error = result.expect_err("no trusted certificate, so no clone");
        println!("without certificates: {error:?}");
    } else {
        println!("cloned: {:?}", result.unwrap().commit);
    }
}
