;; Institution Verification Contract
;; Validates and manages financial entities in the DeFi ecosystem

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-ALREADY-VERIFIED (err u101))
(define-constant ERR-NOT-VERIFIED (err u102))
(define-constant ERR-INVALID-INSTITUTION (err u103))

(define-data-var contract-owner principal tx-sender)

;; Institution data structure
(define-map institutions
  { institution-id: principal }
  {
    name: (string-ascii 100),
    institution-type: (string-ascii 50),
    verified: bool,
    verification-date: uint,
    risk-rating: uint
  }
)

;; Verifier permissions
(define-map authorized-verifiers principal bool)

;; Initialize contract owner as authorized verifier
(map-set authorized-verifiers tx-sender true)

;; Read-only functions
(define-read-only (get-institution (institution-id principal))
  (map-get? institutions { institution-id: institution-id })
)

(define-read-only (is-verified (institution-id principal))
  (match (map-get? institutions { institution-id: institution-id })
    institution (get verified institution)
    false
  )
)

(define-read-only (is-authorized-verifier (verifier principal))
  (default-to false (map-get? authorized-verifiers verifier))
)

;; Public functions
(define-public (add-verifier (verifier principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set authorized-verifiers verifier true))
  )
)

(define-public (verify-institution
  (institution-id principal)
  (name (string-ascii 100))
  (institution-type (string-ascii 50))
  (risk-rating uint)
)
  (begin
    (asserts! (is-authorized-verifier tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? institutions { institution-id: institution-id })) ERR-ALREADY-VERIFIED)
    (ok (map-set institutions
      { institution-id: institution-id }
      {
        name: name,
        institution-type: institution-type,
        verified: true,
        verification-date: block-height,
        risk-rating: risk-rating
      }
    ))
  )
)

(define-public (revoke-verification (institution-id principal))
  (begin
    (asserts! (is-authorized-verifier tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-some (map-get? institutions { institution-id: institution-id })) ERR-NOT-VERIFIED)
    (ok (map-delete institutions { institution-id: institution-id }))
  )
)
