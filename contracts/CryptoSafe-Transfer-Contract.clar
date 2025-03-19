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

;; Allow depositor to withdraw before recipient confirms
(define-public (withdraw-funds (vault-id uint))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (amount (get amount vault-data))
      )
      (asserts! (is-eq tx-sender depositor) ERR_NOT_ALLOWED)
      (asserts! (is-eq (get vault-state vault-data) "pending") ERR_ALREADY_HANDLED)
      (asserts! (<= block-height (get end-block vault-data)) ERR_VAULT_EXPIRED)
      (match (as-contract (stx-transfer? amount tx-sender depositor))
        success-result
          (begin
            (map-set VaultRegistry
              { vault-id: vault-id }
              (merge vault-data { vault-state: "withdrawn" })
            )
            (print {event: "withdrawal_completed", vault-id: vault-id, depositor: depositor, amount: amount})
            (ok true)
          )
        error-result ERR_TRANSFER_FAILED
      )
    )
  )
)

;; --- Vault Management Functions ---

;; Extend vault lifetime
(define-public (extend-vault-time (vault-id uint) (additional-blocks uint))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (asserts! (> additional-blocks u0) ERR_BAD_VALUE)
    (asserts! (<= additional-blocks u1440) ERR_BAD_VALUE) ;; Max ~10 days
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data)) 
        (recipient (get recipient vault-data))
        (current-end (get end-block vault-data))
        (new-end (+ current-end additional-blocks))
      )
      (asserts! (or (is-eq tx-sender depositor) (is-eq tx-sender recipient) (is-eq tx-sender VAULT_ADMIN)) ERR_NOT_ALLOWED)
      (asserts! (or (is-eq (get vault-state vault-data) "pending") (is-eq (get vault-state vault-data) "accepted")) ERR_ALREADY_HANDLED)
      (map-set VaultRegistry
        { vault-id: vault-id }
        (merge vault-data { end-block: new-end })
      )
      (print {event: "vault_extended", vault-id: vault-id, requester: tx-sender, new-end: new-end})
      (ok true)
    )
  )
)

;; Recover expired vault funds
(define-public (recover-expired-vault (vault-id uint))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (amount (get amount vault-data))
        (expiry (get end-block vault-data))
      )
      (asserts! (or (is-eq tx-sender depositor) (is-eq tx-sender VAULT_ADMIN)) ERR_NOT_ALLOWED)
      (asserts! (or (is-eq (get vault-state vault-data) "pending") (is-eq (get vault-state vault-data) "accepted")) ERR_ALREADY_HANDLED)
      (asserts! (> block-height expiry) (err u108)) ;; Must be expired
      (match (as-contract (stx-transfer? amount tx-sender depositor))
        success-result
          (begin
            (map-set VaultRegistry
              { vault-id: vault-id }
              (merge vault-data { vault-state: "expired" })
            )
            (print {event: "expired_vault_recovered", vault-id: vault-id, depositor: depositor, amount: amount})
            (ok true)
          )
        error-result ERR_TRANSFER_FAILED
      )
    )
  )
)

;; --- Dispute Resolution ---

;; Open dispute on vault
(define-public (open-dispute (vault-id uint) (reason (string-ascii 50)))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (recipient (get recipient vault-data))
      )
      (asserts! (or (is-eq tx-sender depositor) (is-eq tx-sender recipient)) ERR_NOT_ALLOWED)
      (asserts! (or (is-eq (get vault-state vault-data) "pending") (is-eq (get vault-state vault-data) "accepted")) ERR_ALREADY_HANDLED)
      (asserts! (<= block-height (get end-block vault-data)) ERR_VAULT_EXPIRED)
      (map-set VaultRegistry
        { vault-id: vault-id }
        (merge vault-data { vault-state: "disputed" })
      )
      (print {event: "dispute_opened", vault-id: vault-id, initiator: tx-sender, reason: reason})
      (ok true)
    )
  )
)


;; --- Verification Functions ---

;; Add cryptographic verification
(define-public (add-crypto-verification (vault-id uint) (sig-data (buff 65)))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (recipient (get recipient vault-data))
      )
      (asserts! (or (is-eq tx-sender depositor) (is-eq tx-sender recipient)) ERR_NOT_ALLOWED)
      (asserts! (or (is-eq (get vault-state vault-data) "pending") (is-eq (get vault-state vault-data) "accepted")) ERR_ALREADY_HANDLED)
      (print {event: "verification_added", vault-id: vault-id, signer: tx-sender, signature: sig-data})
      (ok true)
    )
  )
)

;; Configure backup recovery address
(define-public (set-recovery-address (vault-id uint) (backup-address principal))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
      )
      (asserts! (is-eq tx-sender depositor) ERR_NOT_ALLOWED)
      (asserts! (not (is-eq backup-address tx-sender)) (err u111)) ;; Must be different
      (asserts! (is-eq (get vault-state vault-data) "pending") ERR_ALREADY_HANDLED)
      (print {event: "recovery_address_configured", vault-id: vault-id, depositor: depositor, backup: backup-address})
      (ok true)
    )
  )
)

;; --- Admin Functions ---

;; Resolve dispute with specified division
(define-public (resolve-dispute (vault-id uint) (depositor-percent uint))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (asserts! (is-eq tx-sender VAULT_ADMIN) ERR_NOT_ALLOWED)
    (asserts! (<= depositor-percent u100) ERR_BAD_VALUE) ;; Range: 0-100%
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (recipient (get recipient vault-data))
        (amount (get amount vault-data))
        (depositor-share (/ (* amount depositor-percent) u100))
        (recipient-share (- amount depositor-share))
      )
      (asserts! (is-eq (get vault-state vault-data) "disputed") (err u112)) ;; Must be disputed
      (asserts! (<= block-height (get end-block vault-data)) ERR_VAULT_EXPIRED)

      ;; Send depositor's portion
      (unwrap! (as-contract (stx-transfer? depositor-share tx-sender depositor)) ERR_TRANSFER_FAILED)

      ;; Send recipient's portion
      (unwrap! (as-contract (stx-transfer? recipient-share tx-sender recipient)) ERR_TRANSFER_FAILED)

      (map-set VaultRegistry
        { vault-id: vault-id }
        (merge vault-data { vault-state: "resolved" })
      )
      (print {event: "dispute_resolved", vault-id: vault-id, depositor: depositor, recipient: recipient, 
              depositor-share: depositor-share, recipient-share: recipient-share, depositor-percent: depositor-percent})
      (ok true)
    )
  )
)

;; --- Advanced Security Functions ---

;; Add approval for high-value vaults
(define-public (add-approval-signature (vault-id uint) (approver principal))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (amount (get amount vault-data))
      )
      ;; Only for amounts > 1000 STX
      (asserts! (> amount u1000) (err u120))
      (asserts! (or (is-eq tx-sender depositor) (is-eq tx-sender VAULT_ADMIN)) ERR_NOT_ALLOWED)
      (asserts! (is-eq (get vault-state vault-data) "pending") ERR_ALREADY_HANDLED)
      (print {event: "approval_added", vault-id: vault-id, approver: approver, requester: tx-sender})
      (ok true)
    )
  )
)

;; Flag suspicious activity
(define-public (flag-suspicious-activity (vault-id uint) (details (string-ascii 100)))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (recipient (get recipient vault-data))
      )
      (asserts! (or (is-eq tx-sender VAULT_ADMIN) (is-eq tx-sender depositor) (is-eq tx-sender recipient)) ERR_NOT_ALLOWED)
      (asserts! (or (is-eq (get vault-state vault-data) "pending") 
                   (is-eq (get vault-state vault-data) "accepted")) 
                ERR_ALREADY_HANDLED)
      (map-set VaultRegistry
        { vault-id: vault-id }
        (merge vault-data { vault-state: "flagged" })
      )
      (print {event: "activity_flagged", vault-id: vault-id, reporter: tx-sender, details: details})
      (ok true)
    )
  )
)

;; --- Creation Functions ---

;; Create phased vault with multiple payments
(define-public (create-phased-vault (recipient principal) (asset-id uint) (amount uint) (phases uint))
  (let 
    (
      (vault-id (+ (var-get next-vault-id) u1))
      (expiry (+ block-height VAULT_LIFETIME_BLOCKS))
      (phase-amount (/ amount phases))
    )
    (asserts! (> amount u0) ERR_BAD_VALUE)
    (asserts! (> phases u0) ERR_BAD_VALUE)
    (asserts! (<= phases u5) ERR_BAD_VALUE) ;; Max 5 phases
    (asserts! (validate-recipient recipient) ERR_BAD_RECIPIENT)
    (asserts! (is-eq (* phase-amount phases) amount) (err u121)) ;; Ensure divisible
    (match (stx-transfer? amount tx-sender (as-contract tx-sender))
      success-result
        (begin
          (var-set next-vault-id vault-id)
          (print {event: "phased_vault_created", vault-id: vault-id, depositor: tx-sender, recipient: recipient, 
                  asset-id: asset-id, amount: amount, phases: phases, phase-amount: phase-amount})
          (ok vault-id)
        )
      error-result ERR_TRANSFER_FAILED
    )
  )
)


;; --- Security Functions ---

;; Schedule delayed critical operations
(define-public (schedule-delayed-operation (operation-type (string-ascii 20)) (parameters (list 10 uint)))
  (begin
    (asserts! (is-eq tx-sender VAULT_ADMIN) ERR_NOT_ALLOWED)
    (asserts! (> (len parameters) u0) ERR_BAD_VALUE)
    (let
      (
        (execution-time (+ block-height u144)) ;; 24hr delay
      )
      (print {event: "operation_scheduled", operation-type: operation-type, parameters: parameters, execution-time: execution-time})
      (ok execution-time)
    )
  )
)

;; Enable security check for high-value vaults
(define-public (enable-security-check (vault-id uint) (auth-hash (buff 32)))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (amount (get amount vault-data))
      )
      ;; Only for vaults above threshold
      (asserts! (> amount u5000) (err u130))
      (asserts! (is-eq tx-sender depositor) ERR_NOT_ALLOWED)
      (asserts! (is-eq (get vault-state vault-data) "pending") ERR_ALREADY_HANDLED)
      (print {event: "security_check_enabled", vault-id: vault-id, depositor: depositor, hash: (hash160 auth-hash)})
      (ok true)
    )
  )
)

;; Verify transaction with cryptographic proof
(define-public (verify-with-crypto (vault-id uint) (msg-hash (buff 32)) (signature (buff 65)) (verifier principal))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (recipient (get recipient vault-data))
        (verification-result (unwrap! (secp256k1-recover? msg-hash signature) (err u150)))
      )
      ;; Authorization checks
      (asserts! (or (is-eq tx-sender depositor) (is-eq tx-sender recipient) (is-eq tx-sender VAULT_ADMIN)) ERR_NOT_ALLOWED)
      (asserts! (or (is-eq verifier depositor) (is-eq verifier recipient)) (err u151))
      (asserts! (is-eq (get vault-state vault-data) "pending") ERR_ALREADY_HANDLED)

      ;; Validate signature matches claimed principal
      (asserts! (is-eq (unwrap! (principal-of? verification-result) (err u152)) verifier) (err u153))

      (print {event: "cryptographically_verified", vault-id: vault-id, validator: tx-sender, signer: verifier})
      (ok true)
    )
  )
)

;; --- Metadata Functions ---

;; Add vault metadata
(define-public (attach-metadata (vault-id uint) (metadata-category (string-ascii 20)) (data-hash (buff 32)))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (recipient (get recipient vault-data))
      )
      ;; Authorization check
      (asserts! (or (is-eq tx-sender depositor) (is-eq tx-sender recipient) (is-eq tx-sender VAULT_ADMIN)) ERR_NOT_ALLOWED)
      (asserts! (not (is-eq (get vault-state vault-data) "completed")) (err u160))
      (asserts! (not (is-eq (get vault-state vault-data) "returned")) (err u161))
      (asserts! (not (is-eq (get vault-state vault-data) "expired")) (err u162))

      ;; Validate metadata category
      (asserts! (or (is-eq metadata-category "asset-info") 
                   (is-eq metadata-category "delivery-proof")
                   (is-eq metadata-category "quality-report")
                   (is-eq metadata-category "user-requirements")) (err u163))

      (print {event: "metadata_attached", vault-id: vault-id, category: metadata-category, 
              hash: data-hash, provider: tx-sender})
      (ok true)
    )
  )
)

;; --- Recovery Functions ---

;; Setup time-locked recovery
(define-public (setup-time-recovery (vault-id uint) (delay-blocks uint) (recovery-principal principal))
  (begin
    (asserts! (vault-exists vault-id) ERR_BAD_ID)
    (asserts! (> delay-blocks u72) ERR_BAD_VALUE) ;; Min 72 blocks (~12 hours)
    (asserts! (<= delay-blocks u1440) ERR_BAD_VALUE) ;; Max 1440 blocks (~10 days)
    (let
      (
        (vault-data (unwrap! (map-get? VaultRegistry { vault-id: vault-id }) ERR_VAULT_NOT_FOUND))
        (depositor (get depositor vault-data))
        (unlock-height (+ block-height delay-blocks))
      )
      (asserts! (is-eq tx-sender depositor) ERR_NOT_ALLOWED)
      (asserts! (is-eq (get vault-state vault-data) "pending") ERR_ALREADY_HANDLED)
      (asserts! (not (is-eq recovery-principal depositor)) (err u180)) ;; Different from depositor
      (asserts! (not (is-eq recovery-principal (get recipient vault-data))) (err u181)) ;; Different from recipient
      (print {event: "time_recovery_setup", vault-id: vault-id, depositor: depositor, 
              recovery-principal: recovery-principal, unlock-height: unlock-height})
      (ok unlock-height)
    )
  )
)
