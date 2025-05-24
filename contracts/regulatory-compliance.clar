;; Regulatory Compliance Contract
;; Ensures market rule adherence and compliance monitoring

(define-constant ERR-NOT-AUTHORIZED (err u500))
(define-constant ERR-COMPLIANCE-VIOLATION (err u501))
(define-constant ERR-INVALID-RULE (err u502))
(define-constant ERR-PARTICIPANT-SUSPENDED (err u503))

(define-data-var contract-owner principal tx-sender)

;; Compliance status
(define-constant COMPLIANT u1)
(define-constant NON-COMPLIANT u2)
(define-constant SUSPENDED u3)

;; Compliance rules
(define-map compliance-rules
  { rule-id: uint }
  {
    description: (string-ascii 200),
    severity: uint, ;; 1-5 scale
    active: bool,
    created-date: uint
  }
)

;; Participant compliance status
(define-map participant-compliance
  { participant: principal }
  {
    status: uint,
    violations: uint,
    last-check: uint,
    suspension-end: uint
  }
)

;; Compliance violations
(define-map violations
  { violation-id: uint }
  {
    participant: principal,
    rule-id: uint,
    severity: uint,
    reported-date: uint,
    resolved: bool
  }
)

(define-data-var next-rule-id uint u1)
(define-data-var next-violation-id uint u1)

;; Compliance officers
(define-map compliance-officers principal bool)

;; Initialize contract owner as compliance officer
(map-set compliance-officers tx-sender true)

;; Read-only functions
(define-read-only (get-compliance-status (participant principal))
  (match (map-get? participant-compliance { participant: participant })
    status (get status status)
    COMPLIANT
  )
)

(define-read-only (get-compliance-rule (rule-id uint))
  (map-get? compliance-rules { rule-id: rule-id })
)

(define-read-only (get-violation (violation-id uint))
  (map-get? violations { violation-id: violation-id })
)

(define-read-only (is-compliance-officer (officer principal))
  (default-to false (map-get? compliance-officers officer))
)

(define-read-only (is-participant-suspended (participant principal))
  (match (map-get? participant-compliance { participant: participant })
    compliance
      (and
        (is-eq (get status compliance) SUSPENDED)
        (> (get suspension-end compliance) block-height)
      )
    false
  )
)

;; Public functions
(define-public (add-compliance-officer (officer principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set compliance-officers officer true))
  )
)

(define-public (create-compliance-rule
  (description (string-ascii 200))
  (severity uint)
)
  (let
    (
      (rule-id (var-get next-rule-id))
    )
    (asserts! (is-compliance-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= severity u1) (<= severity u5)) ERR-INVALID-RULE)
    (map-set compliance-rules
      { rule-id: rule-id }
      {
        description: description,
        severity: severity,
        active: true,
        created-date: block-height
      }
    )
    (var-set next-rule-id (+ rule-id u1))
    (ok rule-id)
  )
)

(define-public (report-violation
  (participant principal)
  (rule-id uint)
)
  (let
    (
      (rule (unwrap! (map-get? compliance-rules { rule-id: rule-id }) ERR-INVALID-RULE))
      (violation-id (var-get next-violation-id))
      (current-compliance (default-to
        { status: COMPLIANT, violations: u0, last-check: block-height, suspension-end: u0 }
        (map-get? participant-compliance { participant: participant })
      ))
    )
    (asserts! (is-compliance-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (get active rule) ERR-INVALID-RULE)

    ;; Record violation
    (map-set violations
      { violation-id: violation-id }
      {
        participant: participant,
        rule-id: rule-id,
        severity: (get severity rule),
        reported-date: block-height,
        resolved: false
      }
    )

    ;; Update participant compliance status
    (let
      (
        (new-violations (+ (get violations current-compliance) u1))
        (new-status (if (>= new-violations u3) SUSPENDED NON-COMPLIANT))
        (suspension-duration (if (is-eq new-status SUSPENDED) u1000 u0)) ;; 1000 blocks suspension
      )
      (map-set participant-compliance
        { participant: participant }
        {
          status: new-status,
          violations: new-violations,
          last-check: block-height,
          suspension-end: (if (> suspension-duration u0) (+ block-height suspension-duration) u0)
        }
      )
    )

    (var-set next-violation-id (+ violation-id u1))
    (ok violation-id)
  )
)

(define-public (resolve-violation (violation-id uint))
  (let
    (
      (violation (unwrap! (map-get? violations { violation-id: violation-id }) ERR-INVALID-RULE))
    )
    (asserts! (is-compliance-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (not (get resolved violation)) ERR-COMPLIANCE-VIOLATION)
    (map-set violations
      { violation-id: violation-id }
      (merge violation { resolved: true })
    )
    (ok true)
  )
)

(define-public (check-compliance (participant principal))
  (begin
    (asserts! (not (is-participant-suspended participant)) ERR-PARTICIPANT-SUSPENDED)
    (match (map-get? participant-compliance { participant: participant })
      compliance
        (map-set participant-compliance
          { participant: participant }
          (merge compliance { last-check: block-height })
        )
      (map-set participant-compliance
        { participant: participant }
        { status: COMPLIANT, violations: u0, last-check: block-height, suspension-end: u0 }
      )
    )
    (ok true)
  )
)

(define-public (reinstate-participant (participant principal))
  (let
    (
      (compliance (unwrap! (map-get? participant-compliance { participant: participant }) ERR-INVALID-RULE))
    )
    (asserts! (is-compliance-officer tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status compliance) SUSPENDED) ERR-COMPLIANCE-VIOLATION)
    (map-set participant-compliance
      { participant: participant }
      (merge compliance
        {
          status: COMPLIANT,
          suspension-end: u0,
          last-check: block-height
        }
      )
    )
    (ok true)
  )
)
