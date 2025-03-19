;; CryptoSafe Transfer Smart Contract
;; Enables secure digital asset custody with verification and arbitration capabilities

;; Core constants
(define-constant VAULT_ADMIN tx-sender)
(define-constant ERR_NOT_ALLOWED (err u100))
(define-constant ERR_VAULT_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_HANDLED (err u102))
(define-constant ERR_TRANSFER_FAILED (err u103))
(define-constant ERR_BAD_ID (err u104))
(define-constant ERR_BAD_VALUE (err u105))
(define-constant ERR_BAD_RECIPIENT (err u106))
(define-constant ERR_VAULT_EXPIRED (err u107))
(define-constant VAULT_LIFETIME_BLOCKS u1008) ;; ~7 days

;; Primary data storage
(define-map VaultRegistry
  { vault-id: uint }
  {
    depositor: principal,
    recipient: principal,
    asset-id: uint,
    amount: uint,
    vault-state: (string-ascii 10),
    start-block: uint,
    end-block: uint
  }
)

;; Vault ID tracking
(define-data-var next-vault-id uint u0)

;; --- Helper Functions ---

;; Check if vault ID exists
(define-private (vault-exists (vault-id uint))
  (<= vault-id (var-get next-vault-id))
)

;; Validate recipient isn't contract caller
(define-private (validate-recipient (recipient principal))
  (and 
    (not (is-eq recipient tx-sender))
    (not (is-eq recipient (as-contract tx-sender)))
  )
)

;; --- Core Functions ---

;; Release funds to recipient
(define-public (complete-transfer (vault-id uint))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (recipient (get recipient vault-data))
        (amount (get amount vault-data))
        (asset-id (get asset-id vault-data))
      )
      (asserts! (or (is-eq tx-sender VAULT_ADMIN) (is-eq tx-sender (get depositor vault-data))) ERR_NOT_ALLOWED)
      (asserts! (is-eq (get vault-state vault-data) "pending") ERR_ALREADY_HANDLED)
      (asserts! (<= block-height (get end-block vault-data)) ERR_VAULT_EXPIRED)
      (match (as-contract (stx-transfer? amount tx-sender recipient))
        success-result
          (begin
            (map-set VaultRegistry
              { vault-id: vault-id }
              (merge vault-data { vault-state: "completed" })
            )
            (print {event: "transfer_completed", vault-id: vault-id, recipient: recipient, asset-id: asset-id, amount: amount})
            (ok true)
          )
        error-result ERR_TRANSFER_FAILED
      )
    )
  )
)

;; Return funds to depositor
(define-public (return-funds (vault-id uint))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (amount (get amount vault-data))
      )
      (asserts! (is-eq tx-sender VAULT_ADMIN) ERR_NOT_ALLOWED)
      (asserts! (is-eq (get vault-state vault-data) "pending") ERR_ALREADY_HANDLED)
      (match (as-contract (stx-transfer? amount tx-sender depositor))
        success-result
          (begin
            (map-set VaultRegistry
              { vault-id: vault-id }
              (merge vault-data { vault-state: "returned" })
            )
            (print {event: "funds_returned", vault-id: vault-id, depositor: depositor, amount: amount})
            (ok true)
          )
        error-result ERR_TRANSFER_FAILED
      )
    )
  )
)

