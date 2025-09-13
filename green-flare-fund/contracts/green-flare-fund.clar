;; GreenFlareImpact - Advanced Impact Mining Volunteer Coordination Platform

;; Error constants
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-INSUFFICIENT-BALANCE (err u101))
(define-constant ERR-INITIATIVE-NOT-FOUND (err u102))
(define-constant ERR-VALIDATION-PERIOD-ENDED (err u103))
(define-constant ERR-INVALID-INITIATIVE-TYPE (err u104))
(define-constant ERR-ALREADY-VALIDATED (err u105))
(define-constant ERR-INITIATIVE-NOT-ACTIVE (err u106))
(define-constant ERR-INSUFFICIENT-IMPACT-POWER (err u107))
(define-constant ERR-MILESTONE-NOT-FOUND (err u108))
(define-constant ERR-NGO-VERIFICATION-FAILED (err u109))
(define-constant ERR-SUPERMAJORITY-REQUIRED (err u110))
(define-constant ERR-TIME-LOCK-ACTIVE (err u111))
(define-constant ERR-INVALID-AMOUNT (err u112))
(define-constant ERR-REPUTATION-TOO-LOW (err u113))
(define-constant ERR-INITIATIVE-ALREADY-EXECUTED (err u114))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MICRO-IMPACT-THRESHOLD u1000)
(define-constant MEGA-IMPACT-THRESHOLD u50000)
(define-constant SUPERMAJORITY-THRESHOLD u75)
(define-constant TIME-LOCK-PERIOD u144) ;; blocks
(define-constant MAX-VALIDATION-PERIOD u1008) ;; blocks

;; Data variables
(define-data-var initiative-counter uint u0)
(define-data-var total-community-treasury uint u1000000) ;; Initial treasury
(define-data-var ngo-verifier-address principal CONTRACT-OWNER)
(define-data-var minimum-impact-score uint u10)
(define-data-var proof-of-impact-enabled bool true)

;; Initiative types
(define-constant INITIATIVE-TYPE-LOCAL u1)
(define-constant INITIATIVE-TYPE-REGIONAL u2)
(define-constant INITIATIVE-TYPE-GLOBAL u3)

;; Initiative status
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-APPROVED u2)
(define-constant STATUS-REJECTED u3)
(define-constant STATUS-EXECUTED u4)

;; Data maps
(define-map initiatives
    { initiative-id: uint }
    {
        proposer: principal,
        title: (string-ascii 100),
        description: (string-ascii 500),
        gft-requested: uint,
        initiative-type: uint,
        status: uint,
        support-votes: uint,
        oppose-votes: uint,
        validation-end-block: uint,
        time-lock-end: uint,
        impact-feasibility-score: uint,
        execution-block: uint,
        category: (string-ascii 50)
    }
)

(define-map volunteer-validations
    { initiative-id: uint, validator: principal }
    {
        impact-power-used: uint,
        validation-direction: bool,
        gft-committed: uint,
        conviction-weight: uint
    }
)

(define-map volunteer-reputation
    { volunteer: principal }
    {
        impact-score: uint,
        successful-validations: uint,
        total-validations: uint,
        conviction-power: uint,
        expertise-category: (string-ascii 50)
    }
)

(define-map initiative-milestones
    { initiative-id: uint, milestone-id: uint }
    {
        description: (string-ascii 200),
        amount: uint,
        completed: bool,
        verified-by-ngo: bool,
        completion-block: uint
    }
)

(define-map impact-escrow
    { initiative-id: uint }
    {
        total-amount: uint,
        released-amount: uint,
        milestones-count: uint,
        beneficiary: principal
    }
)

(define-map impact-ripple-tracking
    { volunteer: principal, category: (string-ascii 50) }
    {
        accumulated-power: uint,
        last-activity-block: uint,
        consistency-score: uint
    }
)

;; GFT balance tracking
(define-map gft-balances { volunteer: principal } { balance: uint })

;; Helper functions
(define-private (determine-initiative-type (amount uint))
    (if (<= amount MICRO-IMPACT-THRESHOLD)
        INITIATIVE-TYPE-LOCAL
        (if (<= amount MEGA-IMPACT-THRESHOLD)
            INITIATIVE-TYPE-REGIONAL
            INITIATIVE-TYPE-GLOBAL
        )
    )
)

(define-private (calculate-validation-period (initiative-type uint))
    (if (is-eq initiative-type INITIATIVE-TYPE-LOCAL)
        u72  ;; ~12 hours
        (if (is-eq initiative-type INITIATIVE-TYPE-REGIONAL)
            u432 ;; ~3 days
            u1008 ;; ~7 days
        )
    )
)

(define-private (calculate-impact-mining-power (gft uint))
    ;; Simple quadratic scaling using integer approximation
    ;; For impact mining: mining_power = sqrt(gft)
    (if (<= gft u1)
        u1
        (if (<= gft u4)
            u2
            (if (<= gft u9)
                u3
                (if (<= gft u16)
                    u4
                    (if (<= gft u25)
                        u5
                        (if (<= gft u36)
                            u6
                            (if (<= gft u49)
                                u7
                                (if (<= gft u64)
                                    u8
                                    (if (<= gft u81)
                                        u9
                                        (if (<= gft u100)
                                            u10
                                            ;; For larger amounts, use simplified scaling
                                            (+ u10 (/ (- gft u100) u20))
                                        )
                                    )
                                )
                            )
                        )
                    )
                )
            )
        )
    )
)

(define-private (calculate-impact-feasibility-score (amount uint) (category (string-ascii 50)))
    ;; Simplified impact scoring based on amount and category
    (let ((base-score (if (<= amount u10000) u80 u60)))
        (if (is-eq category "environmental")
            (+ base-score u10)
            (if (is-eq category "social")
                (+ base-score u5)
                base-score
            )
        )
    )
)

(define-private (get-ripple-bonus (volunteer principal) (category (string-ascii 50)))
    (let ((ripple-data (map-get? impact-ripple-tracking { volunteer: volunteer, category: category })))
        (if (is-some ripple-data)
            (let ((data (unwrap-panic ripple-data)))
                (/ (get accumulated-power data) u10)
            )
            u0
        )
    )
)

(define-private (update-impact-ripple (volunteer principal) (category (string-ascii 50)))
    (let ((current-data (default-to 
                            { accumulated-power: u0, last-activity-block: u0, consistency-score: u0 }
                            (map-get? impact-ripple-tracking { volunteer: volunteer, category: category }))))
        (map-set impact-ripple-tracking { volunteer: volunteer, category: category }
            {
                accumulated-power: (+ (get accumulated-power current-data) u1),
                last-activity-block: block-height,
                consistency-score: (+ (get consistency-score current-data) u1)
            }
        )
    )
)

;; Read-only functions
(define-read-only (get-volunteer-reputation (volunteer principal))
    (default-to 
        { impact-score: u50, successful-validations: u0, total-validations: u0, conviction-power: u0, expertise-category: "" }
        (map-get? volunteer-reputation { volunteer: volunteer })
    )
)

(define-read-only (get-initiative (initiative-id uint))
    (map-get? initiatives { initiative-id: initiative-id })
)

(define-read-only (get-volunteer-validation (initiative-id uint) (validator principal))
    (map-get? volunteer-validations { initiative-id: initiative-id, validator: validator })
)

(define-read-only (get-gft-balance (volunteer principal))
    (default-to u0 (get balance (map-get? gft-balances { volunteer: volunteer })))
)

(define-read-only (get-community-treasury)
    (var-get total-community-treasury)
)

(define-read-only (get-initiative-count)
    (var-get initiative-counter)
)

;; Administrative functions
(define-public (set-ngo-verifier (new-verifier principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set ngo-verifier-address new-verifier)
        (ok true)
    )
)

(define-public (set-minimum-impact-score (new-min uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set minimum-impact-score new-min)
        (ok true)
    )
)

(define-public (toggle-proof-of-impact)
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (var-set proof-of-impact-enabled (not (var-get proof-of-impact-enabled)))
        (ok true)
    )
)

(define-public (mint-gft-tokens (recipient principal) (amount uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (let ((current-balance (get-gft-balance recipient)))
            (map-set gft-balances { volunteer: recipient }
                { balance: (+ current-balance amount) }
            )
            (ok true)
        )
    )
)

(define-public (fund-community-treasury (amount uint))
    (begin
        (asserts! (> amount u0) ERR-INVALID-AMOUNT)
        (var-set total-community-treasury (+ (var-get total-community-treasury) amount))
        (ok true)
    )
)

;; Core initiative creation
(define-public (create-initiative 
    (title (string-ascii 100))
    (description (string-ascii 500))
    (gft-requested uint)
    (category (string-ascii 50)))
    (let (
        (initiative-id (+ (var-get initiative-counter) u1))
        (volunteer-rep (get-volunteer-reputation tx-sender))
        (initiative-type (determine-initiative-type gft-requested))
        (validation-period (calculate-validation-period initiative-type))
        (impact-score (if (var-get proof-of-impact-enabled) 
                     (calculate-impact-feasibility-score gft-requested category)
                     u50))
    )
        (asserts! (>= (get impact-score volunteer-rep) (var-get minimum-impact-score)) ERR-REPUTATION-TOO-LOW)
        (asserts! (> gft-requested u0) ERR-INVALID-AMOUNT)
        (asserts! (<= gft-requested (var-get total-community-treasury)) ERR-INSUFFICIENT-BALANCE)
        
        (map-set initiatives { initiative-id: initiative-id }
            {
                proposer: tx-sender,
                title: title,
                description: description,
                gft-requested: gft-requested,
                initiative-type: initiative-type,
                status: STATUS-ACTIVE,
                support-votes: u0,
                oppose-votes: u0,
                validation-end-block: (+ block-height validation-period),
                time-lock-end: (if (is-eq initiative-type INITIATIVE-TYPE-GLOBAL)
                                  (+ block-height TIME-LOCK-PERIOD)
                                  block-height),
                impact-feasibility-score: impact-score,
                execution-block: u0,
                category: category
            }
        )
        
        ;; Create impact escrow
        (map-set impact-escrow { initiative-id: initiative-id }
            {
                total-amount: gft-requested,
                released-amount: u0,
                milestones-count: u0,
                beneficiary: tx-sender
            }
        )
        
        (var-set initiative-counter initiative-id)
        (ok initiative-id)
    )
)

;; Impact mining validation implementation
(define-public (validate-initiative 
    (initiative-id uint)
    (support-initiative bool)
    (gft-committed uint))
    (let (
        (initiative (unwrap! (map-get? initiatives { initiative-id: initiative-id }) ERR-INITIATIVE-NOT-FOUND))
        (volunteer-rep (get-volunteer-reputation tx-sender))
        (volunteer-balance (get-gft-balance tx-sender))
        (impact-power (calculate-impact-mining-power gft-committed))
        (ripple-bonus (get-ripple-bonus tx-sender (get category initiative)))
        (total-impact-power (+ impact-power ripple-bonus))
    )
        (asserts! (is-eq (get status initiative) STATUS-ACTIVE) ERR-INITIATIVE-NOT-ACTIVE)
        (asserts! (<= block-height (get validation-end-block initiative)) ERR-VALIDATION-PERIOD-ENDED)
        (asserts! (>= volunteer-balance gft-committed) ERR-INSUFFICIENT-BALANCE)
        (asserts! (is-none (map-get? volunteer-validations { initiative-id: initiative-id, validator: tx-sender })) ERR-ALREADY-VALIDATED)
        (asserts! (> total-impact-power u0) ERR-INSUFFICIENT-IMPACT-POWER)
        (asserts! (> gft-committed u0) ERR-INVALID-AMOUNT)
        
        ;; Record validation
        (map-set volunteer-validations { initiative-id: initiative-id, validator: tx-sender }
            {
                impact-power-used: total-impact-power,
                validation-direction: support-initiative,
                gft-committed: gft-committed,
                conviction-weight: ripple-bonus
            }
        )
        
        ;; Update initiative vote counts
        (if support-initiative
            (map-set initiatives { initiative-id: initiative-id }
                (merge initiative { support-votes: (+ (get support-votes initiative) total-impact-power) }))
            (map-set initiatives { initiative-id: initiative-id }
                (merge initiative { oppose-votes: (+ (get oppose-votes initiative) total-impact-power) }))
        )
        
        ;; Update impact ripple tracking
        (update-impact-ripple tx-sender (get category initiative))
        
        ;; Update volunteer reputation
        (let ((current-rep (get-volunteer-reputation tx-sender)))
            (map-set volunteer-reputation { volunteer: tx-sender }
                (merge current-rep {
                    total-validations: (+ (get total-validations current-rep) u1),
                    conviction-power: (+ (get conviction-power current-rep) ripple-bonus)
                })
            )
        )
        
        ;; Lock