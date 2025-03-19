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


