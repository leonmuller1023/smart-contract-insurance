;; Smart Contract Coverage Insurance System
;; title: smart-contract-coverage
;; version: 1.0.0
;; summary: Comprehensive smart contract insurance coverage with automated claim processing
;; description: This contract provides insurance coverage for smart contract failures, bugs, and vulnerabilities

;; Error constants
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-INVALID-AMOUNT (err u101))
(define-constant ERR-POLICY-NOT-FOUND (err u102))
(define-constant ERR-POLICY-EXPIRED (err u103))
(define-constant ERR-CLAIM-ALREADY-EXISTS (err u104))
(define-constant ERR-CLAIM-NOT-FOUND (err u105))
(define-constant ERR-INSUFFICIENT-FUNDS (err u106))
(define-constant ERR-INVALID-RISK-SCORE (err u107))
(define-constant ERR-CONTRACT-PAUSED (err u108))
(define-constant ERR-INVALID-COVERAGE-TYPE (err u109))
(define-constant ERR-CLAIM-ALREADY-PROCESSED (err u110))

;; Contract constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MIN-PREMIUM u1000000) ;; 1 STX minimum premium
(define-constant MAX-COVERAGE-AMOUNT u1000000000000) ;; 1M STX max coverage
(define-constant BASE-PREMIUM-RATE u100) ;; 1% base rate
(define-constant CLAIM-PROCESSING-TIME u144) ;; ~24 hours in blocks
(define-constant MAX-RISK-SCORE u1000)

;; Coverage types
(define-constant COVERAGE-BUG-PROTECTION u1)
(define-constant COVERAGE-FAILURE-RECOVERY u2)
(define-constant COVERAGE-VULNERABILITY-SHIELD u3)
(define-constant COVERAGE-ECONOMIC-LOSS u4)

;; Data variables
(define-data-var contract-paused bool false)
(define-data-var next-policy-id uint u1)
(define-data-var next-claim-id uint u1)
(define-data-var total-premiums-collected uint u0)
(define-data-var total-claims-paid uint u0)
(define-data-var insurance-pool uint u0)

;; Policy data structure
(define-map policies
    { policy-id: uint }
    {
        owner: principal,
        insured-contract: principal,
        coverage-amount: uint,
        premium-amount: uint,
        coverage-type: uint,
        risk-score: uint,
        start-block: uint,
        end-block: uint,
        is-active: bool
    }
)

;; Claims data structure
(define-map claims
    { claim-id: uint }
    {
        policy-id: uint,
        claimant: principal,
        claim-amount: uint,
        failure-block: uint,
        description: (string-ascii 500),
        evidence-hash: (string-ascii 64),
        status: uint, ;; 0: pending, 1: approved, 2: rejected, 3: paid
        filing-block: uint,
        processing-block: uint
    }
)

;; Policy owner mapping for efficient lookups
(define-map user-policies
    { owner: principal, index: uint }
    { policy-id: uint }
)

;; User policy count tracking
(define-map user-policy-count
    { owner: principal }
    { count: uint }
)

;; Risk assessment data
(define-map contract-risk-scores
    { contract-address: principal }
    { 
        risk-score: uint,
        last-assessment: uint,
        assessment-count: uint
    }
)

;; Premium calculation helpers
(define-map coverage-multipliers
    { coverage-type: uint }
    { multiplier: uint }
)

;; Initialize coverage multipliers
(map-set coverage-multipliers { coverage-type: COVERAGE-BUG-PROTECTION } { multiplier: u100 })
(map-set coverage-multipliers { coverage-type: COVERAGE-FAILURE-RECOVERY } { multiplier: u150 })
(map-set coverage-multipliers { coverage-type: COVERAGE-VULNERABILITY-SHIELD } { multiplier: u200 })
(map-set coverage-multipliers { coverage-type: COVERAGE-ECONOMIC-LOSS } { multiplier: u120 })

;; Public Functions

;; Create new insurance policy
(define-public (create-policy (insured-contract principal) (coverage-amount uint) (coverage-type uint) (duration-blocks uint))
    (let (
        (policy-id (var-get next-policy-id))
        (risk-score (get-or-calculate-risk-score insured-contract))
        (premium (calculate-premium coverage-amount coverage-type risk-score duration-blocks))
        (current-block block-height)
        (end-block (+ current-block duration-blocks))
        (user-count (default-to u0 (get count (map-get? user-policy-count { owner: tx-sender }))))
    )
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (> coverage-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= coverage-amount MAX-COVERAGE-AMOUNT) ERR-INVALID-AMOUNT)
        (asserts! (>= premium MIN-PREMIUM) ERR-INVALID-AMOUNT)
        (asserts! (is-valid-coverage-type coverage-type) ERR-INVALID-COVERAGE-TYPE)
        
        ;; Transfer premium from user
        (try! (stx-transfer? premium tx-sender (as-contract tx-sender)))
        
        ;; Create policy record
        (map-set policies
            { policy-id: policy-id }
            {
                owner: tx-sender,
                insured-contract: insured-contract,
                coverage-amount: coverage-amount,
                premium-amount: premium,
                coverage-type: coverage-type,
                risk-score: risk-score,
                start-block: current-block,
                end-block: end-block,
                is-active: true
            }
        )
        
        ;; Update user policy tracking
        (map-set user-policies
            { owner: tx-sender, index: user-count }
            { policy-id: policy-id }
        )
        (map-set user-policy-count
            { owner: tx-sender }
            { count: (+ user-count u1) }
        )
        
        ;; Update contract variables
        (var-set next-policy-id (+ policy-id u1))
        (var-set total-premiums-collected (+ (var-get total-premiums-collected) premium))
        (var-set insurance-pool (+ (var-get insurance-pool) premium))
        
        (ok policy-id)
    )
)

;; File insurance claim
(define-public (file-claim (policy-id uint) (claim-amount uint) (failure-block uint) (description (string-ascii 500)) (evidence-hash (string-ascii 64)))
    (let (
        (claim-id (var-get next-claim-id))
        (policy (unwrap! (map-get? policies { policy-id: policy-id }) ERR-POLICY-NOT-FOUND))
        (current-block block-height)
    )
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (is-eq (get owner policy) tx-sender) ERR-UNAUTHORIZED)
        (asserts! (get is-active policy) ERR-POLICY-EXPIRED)
        (asserts! (<= current-block (get end-block policy)) ERR-POLICY-EXPIRED)
        (asserts! (> claim-amount u0) ERR-INVALID-AMOUNT)
        (asserts! (<= claim-amount (get coverage-amount policy)) ERR-INVALID-AMOUNT)
        (asserts! (>= failure-block (get start-block policy)) ERR-INVALID-AMOUNT)
        (asserts! (<= failure-block current-block) ERR-INVALID-AMOUNT)
        
        ;; Create claim record
        (map-set claims
            { claim-id: claim-id }
            {
                policy-id: policy-id,
                claimant: tx-sender,
                claim-amount: claim-amount,
                failure-block: failure-block,
                description: description,
                evidence-hash: evidence-hash,
                status: u0, ;; pending
                filing-block: current-block,
                processing-block: u0
            }
        )
        
        (var-set next-claim-id (+ claim-id u1))
        (ok claim-id)
    )
)

;; Process claim (automated or admin)
(define-public (process-claim (claim-id uint) (approved bool))
    (let (
        (claim (unwrap! (map-get? claims { claim-id: claim-id }) ERR-CLAIM-NOT-FOUND))
        (policy (unwrap! (map-get? policies { policy-id: (get policy-id claim) }) ERR-POLICY-NOT-FOUND))
        (current-block block-height)
        (claim-amount (get claim-amount claim))
    )
        (asserts! (not (var-get contract-paused)) ERR-CONTRACT-PAUSED)
        (asserts! (or (is-eq tx-sender CONTRACT-OWNER) 
                     (and (is-eq tx-sender (get claimant claim))
                          (>= current-block (+ (get filing-block claim) CLAIM-PROCESSING-TIME)))) 
                  ERR-UNAUTHORIZED)
        (asserts! (is-eq (get status claim) u0) ERR-CLAIM-ALREADY-PROCESSED)
        (asserts! (>= (var-get insurance-pool) claim-amount) ERR-INSUFFICIENT-FUNDS)
        
        (if approved
            (begin
                ;; Approve and pay claim
                (try! (as-contract (stx-transfer? claim-amount tx-sender (get claimant claim))))
                (map-set claims
                    { claim-id: claim-id }
                    (merge claim {
                        status: u3, ;; paid
                        processing-block: current-block
                    })
                )
                (var-set total-claims-paid (+ (var-get total-claims-paid) claim-amount))
                (var-set insurance-pool (- (var-get insurance-pool) claim-amount))
                (ok true)
            )
            (begin
                ;; Reject claim
                (map-set claims
                    { claim-id: claim-id }
                    (merge claim {
                        status: u2, ;; rejected
                        processing-block: current-block
                    })
                )
                (ok false)
            )
        )
    )
)

;; Admin function to pause/unpause contract
(define-public (set-contract-paused (paused bool))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
        (var-set contract-paused paused)
        (ok paused)
    )
)

;; Add funds to insurance pool
(define-public (add-to-insurance-pool (amount uint))
    (begin
        (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
        (var-set insurance-pool (+ (var-get insurance-pool) amount))
        (ok amount)
    )
)

;; Read-only functions

;; Get policy details
(define-read-only (get-policy (policy-id uint))
    (map-get? policies { policy-id: policy-id })
)

;; Get claim details
(define-read-only (get-claim (claim-id uint))
    (map-get? claims { claim-id: claim-id })
)

;; Get user's policy count
(define-read-only (get-user-policy-count (owner principal))
    (default-to u0 (get count (map-get? user-policy-count { owner: owner })))
)

;; Get user's policy by index
(define-read-only (get-user-policy (owner principal) (index uint))
    (map-get? user-policies { owner: owner, index: index })
)

;; Get contract statistics
(define-read-only (get-contract-stats)
    {
        total-policies: (- (var-get next-policy-id) u1),
        total-claims: (- (var-get next-claim-id) u1),
        total-premiums-collected: (var-get total-premiums-collected),
        total-claims-paid: (var-get total-claims-paid),
        insurance-pool: (var-get insurance-pool),
        contract-paused: (var-get contract-paused)
    }
)

;; Calculate premium for given parameters
(define-read-only (calculate-premium (coverage-amount uint) (coverage-type uint) (risk-score uint) (duration-blocks uint))
    (let (
        (base-premium (* coverage-amount BASE-PREMIUM-RATE))
        (coverage-multiplier (default-to u100 (get multiplier (map-get? coverage-multipliers { coverage-type: coverage-type }))))
        (risk-multiplier (+ u100 (/ (* risk-score u50) u1000)))
        (time-multiplier (/ duration-blocks u4320)) ;; Normalize to ~30 days
    )
        (/ (* (* (* base-premium coverage-multiplier) risk-multiplier) time-multiplier) u1000000)
    )
)

;; Private helper functions

;; Validate coverage type
(define-private (is-valid-coverage-type (coverage-type uint))
    (or (is-eq coverage-type COVERAGE-BUG-PROTECTION)
        (is-eq coverage-type COVERAGE-FAILURE-RECOVERY)
        (is-eq coverage-type COVERAGE-VULNERABILITY-SHIELD)
        (is-eq coverage-type COVERAGE-ECONOMIC-LOSS))
)

;; Get or calculate risk score for a contract
(define-private (get-or-calculate-risk-score (contract-address principal))
    (let (
        (existing-score (map-get? contract-risk-scores { contract-address: contract-address }))
    )
        (match existing-score
            score (get risk-score score)
            ;; Default risk score calculation - in production this would involve code analysis
            (let (
                (calculated-score (calculate-default-risk-score contract-address))
            )
                (map-set contract-risk-scores
                    { contract-address: contract-address }
                    {
                        risk-score: calculated-score,
                        last-assessment: block-height,
                        assessment-count: u1
                    }
                )
                calculated-score
            )
        )
    )
)

;; Calculate default risk score based on contract address
(define-private (calculate-default-risk-score (contract-address principal))
    ;; Simplified risk calculation - in practice this would analyze the contract code
    ;; Using a simple deterministic method based on principal
    (let (
        (address-hash (sha256 (unwrap-panic (to-consensus-buff? contract-address))))
        (hash-value (buff-to-uint-be (unwrap-panic (as-max-len? address-hash u16))))
    )
        (+ u100 (mod hash-value u700)) ;; Risk score between 100-800
    )
)
