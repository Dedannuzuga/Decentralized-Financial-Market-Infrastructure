;; Settlement Protocol Contract
;; Manages transaction finalization and settlement processes

(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-INVALID-TRANSACTION (err u201))
(define-constant ERR-ALREADY-SETTLED (err u202))
(define-constant ERR-SETTLEMENT-FAILED (err u203))
(define-constant ERR-INSUFFICIENT-FUNDS (err u204))

(define-data-var contract-owner principal tx-sender)
(define-data-var settlement-fee uint u1000) ;; 0.1% fee in basis points

;; Transaction states
(define-constant PENDING u0)
(define-constant SETTLED u1)
(define-constant FAILED u2)

;; Settlement transaction structure
(define-map settlement-transactions
  { tx-id: uint }
  {
    sender: principal,
    receiver: principal,
    amount: uint,
    status: uint,
    settlement-date: uint,
    fee-paid: uint
  }
)

(define-data-var next-tx-id uint u1)

;; Authorized settlement agents
(define-map settlement-agents principal bool)

;; Initialize contract owner as settlement agent
(map-set settlement-agents tx-sender true)

;; Read-only functions
(define-read-only (get-transaction (tx-id uint))
  (map-get? settlement-transactions { tx-id: tx-id })
)

(define-read-only (get-settlement-fee)
  (var-get settlement-fee)
)

(define-read-only (is-settlement-agent (agent principal))
  (default-to false (map-get? settlement-agents agent))
)

;; Public functions
(define-public (add-settlement-agent (agent principal))
  (begin
    (asserts! (is-eq tx-sender (var-get contract-owner)) ERR-NOT-AUTHORIZED)
    (ok (map-set settlement-agents agent true))
  )
)

(define-public (initiate-settlement
  (receiver principal)
  (amount uint)
)
  (let
    (
      (tx-id (var-get next-tx-id))
      (fee (/ (* amount (var-get settlement-fee)) u10000))
      (total-amount (+ amount fee))
    )
    (asserts! (>= (stx-get-balance tx-sender) total-amount) ERR-INSUFFICIENT-FUNDS)
    (try! (stx-transfer? total-amount tx-sender (as-contract tx-sender)))
    (map-set settlement-transactions
      { tx-id: tx-id }
      {
        sender: tx-sender,
        receiver: receiver,
        amount: amount,
        status: PENDING,
        settlement-date: u0,
        fee-paid: fee
      }
    )
    (var-set next-tx-id (+ tx-id u1))
    (ok tx-id)
  )
)

(define-public (complete-settlement (tx-id uint))
  (let
    (
      (transaction (unwrap! (map-get? settlement-transactions { tx-id: tx-id }) ERR-INVALID-TRANSACTION))
    )
    (asserts! (is-settlement-agent tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status transaction) PENDING) ERR-ALREADY-SETTLED)
    (try! (as-contract (stx-transfer? (get amount transaction) tx-sender (get receiver transaction))))
    (map-set settlement-transactions
      { tx-id: tx-id }
      (merge transaction { status: SETTLED, settlement-date: block-height })
    )
    (ok true)
  )
)

(define-public (fail-settlement (tx-id uint))
  (let
    (
      (transaction (unwrap! (map-get? settlement-transactions { tx-id: tx-id }) ERR-INVALID-TRANSACTION))
    )
    (asserts! (is-settlement-agent tx-sender) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status transaction) PENDING) ERR-ALREADY-SETTLED)
    (try! (as-contract (stx-transfer? (+ (get amount transaction) (get fee-paid transaction)) tx-sender (get sender transaction))))
    (map-set settlement-transactions
      { tx-id: tx-id }
      (merge transaction { status: FAILED, settlement-date: block-height })
    )
    (ok true)
  )
)
