;; Risk Monitoring Contract
;; Identifies and tracks systemic risks in the financial market

(define-constant ERR-NOT-AUTHORIZED (err u400))
(define-constant ERR-INVALID-RISK-LEVEL (err u401))
(define-constant ERR-RISK-THRESHOLD-EXCEEDED (err u402))

(define-data-var contract-owner principal tx-sender)
(define-data-var system-risk-level uint u0) ;; 0-100 scale
(define-data-var max-risk-threshold uint u80)

;; Risk categories
(define-constant LIQUIDITY-RISK u1)
(define-constant CREDIT-RISK u2)
(define-constant MARKET-RISK u3)
(define-constant OPERATIONAL-RISK u4)

;; Risk assessments for participants
(define-map participant-risks
  { participant: principal }
  {
    liquidity-score: uint,
    credit-score: uint,
    market-exposure: uint,
    operational-score: uint,
    overall-risk: uint,
    last-assessment: uint
  }
)

;; System-wide risk metrics
(define-map system-metrics
  { metric-type: uint }
  {
    current-value: uint,
    threshold: uint,
    last-update: uint,
    alert-triggered: bool
  }
)

;; Risk monitors (authorized to update risk assessments)
(define-map risk-monitors principal bool)

;; Initialize contract owner as risk monitor
(map-set risk-monitors tx-sender true)

;; Initialize system metrics
(map-set system-metrics { metric-type: LIQUIDITY-RISK } { current-value: u0, threshold: u70, last-update: block-height, alert-triggered: false })
(map-set system-metrics { metric-type: CREDIT-RISK } { current-value: u0, threshold: u75, last-update: block-height, alert-triggered: false })
(map-set system-metrics { metric-type: MARKET-RISK } { current-value: u0, threshold: u80, last-update: block-height, alert-triggered: false })
(map-set system-metrics { metric-type: OPERATIONAL-RISK } { current-value: u0, threshold: u60, last-update: block-height, alert-triggered: false })

;; Read-only functions
(define-read-only (get-participant-risk (participant principal))
  (map-get? participant-risks { participant: participant })
)

(define-read-only (get-system-risk-level)
  (var-get system-risk-level)
)

(define-read-only (get-system-metric (metric-type uint))
  (map-get? system-metrics { metric-type: metric-type })
)

(define-read-only (is-risk-monitor (monitor principal))
  (default-to false (map-get? risk-monitors monitor))
)

(define-read-only (check-risk-threshold (participant principal))
  (match (map-get? participant-risks { participant: participant })
    risk (< (get overall-risk risk) (var-get max-risk-threshold))
    true
  )
)

;; Public functions
(define-public (add-risk-monitor (monitor principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set risk-monitors monitor true))
  )
)

(define-public (assess-participant-risk
  (participant principal)
  (liquidity-score uint)
  (credit-score uint)
  (market-exposure uint)
  (operational-score uint)
)
  (let
    (
      (overall-risk (/ (+ liquidity-score credit-score market-exposure operational-score) u4))
    )
    (asserts! (is-risk-monitor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= overall-risk u100) ERR-INVALID-RISK-LEVEL)
    (map-set participant-risks
      { participant: participant }
      {
        liquidity-score: liquidity-score,
        credit-score: credit-score,
        market-exposure: market-exposure,
        operational-score: operational-score,
        overall-risk: overall-risk,
        last-assessment: block-height
      }
    )
    (ok overall-risk)
  )
)

(define-public (update-system-metric (metric-type uint) (new-value uint))
  (let
    (
      (metric (unwrap! (map-get? system-metrics { metric-type: metric-type }) ERR-INVALID-RISK-LEVEL))
    )
    (asserts! (is-risk-monitor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (<= new-value u100) ERR-INVALID-RISK-LEVEL)
    (map-set system-metrics
      { metric-type: metric-type }
      (merge metric
        {
          current-value: new-value,
          last-update: block-height,
          alert-triggered: (>= new-value (get threshold metric))
        }
      )
    )
    ;; Update system-wide risk level
    (var-set system-risk-level (calculate-system-risk))
    (ok new-value)
  )
)

(define-public (trigger-risk-alert (participant principal))
  (let
    (
      (risk (unwrap! (map-get? participant-risks { participant: participant }) ERR-INVALID-RISK-LEVEL))
    )
    (asserts! (is-risk-monitor tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (>= (get overall-risk risk) (var-get max-risk-threshold)) ERR-RISK-THRESHOLD-EXCEEDED)
    (ok true)
  )
)

;; Private functions
(define-private (calculate-system-risk)
  (let
    (
      (liquidity (default-to u0 (get current-value (map-get? system-metrics { metric-type: LIQUIDITY-RISK }))))
      (credit (default-to u0 (get current-value (map-get? system-metrics { metric-type: CREDIT-RISK }))))
      (market (default-to u0 (get current-value (map-get? system-metrics { metric-type: MARKET-RISK }))))
      (operational (default-to u0 (get current-value (map-get? system-metrics { metric-type: OPERATIONAL-RISK }))))
    )
    (/ (+ liquidity credit market operational) u4)
  )
)
