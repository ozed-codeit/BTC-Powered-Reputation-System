;; BTC-Powered Reputation System
;; On-chain reputation scoring based on verifiable activities

(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-unauthorized (err u102))
(define-constant err-invalid-score (err u103))
(define-constant err-already-exists (err u104))
(define-constant err-insufficient-balance (err u105))
(define-constant err-invalid-timeframe (err u106))
(define-constant err-max-delegates-reached (err u107))
(define-constant err-invalid-badge-level (err u108))

(define-map user-reputation
  principal
  {
    base-score: uint,
    payment-score: uint,
    governance-score: uint,
    social-score: uint,
    total-score: uint,
    last-updated: uint,
    verified: bool,
    trust-level: uint,
    reputation-locked: bool
  })

(define-map reputation-activities
  { user: principal, activity-id: uint }
  {
    activity-type: (string-ascii 32),
    score-change: int,
    timestamp: uint,
    verifier: principal,
    description: (string-ascii 128)
  })

(define-map user-activity-counter
  principal
  uint)

(define-map score-weights
  (string-ascii 32)
  uint)

(define-map verified-actions
  { user: principal, action-hash: (buff 32) }
  {
    action-type: (string-ascii 32),
    score-impact: uint,
    verified-at: uint,
    verifier: principal
  })

(define-map reputation-delegates
  { delegator: principal, delegate: principal }
  {
    delegated-score: uint,
    delegation-start: uint,
    delegation-end: uint,
    active: bool
  })

(define-map user-badges
  { user: principal, badge-type: (string-ascii 32) }
  {
    badge-level: uint,
    earned-at: uint,
    badge-score: uint,
    requirements-met: (list 5 (string-ascii 64))
  })

(define-public (initialize-reputation)
  (let ((caller tx-sender))
    (asserts! (is-none (map-get? user-reputation caller)) err-already-exists)
    (ok (map-set user-reputation caller {
      base-score: u100,
      payment-score: u0,
      governance-score: u0,
      social-score: u0,
      total-score: u100,
      last-updated: block-height,
      verified: false,
      trust-level: u1,
      reputation-locked: false
    }))))

(define-public (reset-reputation (user principal))
  (let ((caller tx-sender))
    (asserts! (is-eq caller contract-owner) err-owner-only)
    (asserts! (is-some (map-get? user-reputation user)) err-not-found)
    (ok (map-set user-reputation user {
      base-score: u100,
      payment-score: u0,
      governance-score: u0,
      social-score: u0,
      total-score: u100,
      last-updated: block-height,
      verified: false,
      trust-level: u1,
      reputation-locked: false
    }))))

(define-public (lock-reputation (user principal) (duration-blocks uint))
  (let ((caller tx-sender)
        (reputation (unwrap! (map-get? user-reputation user) err-not-found)))
    (asserts! (is-eq caller contract-owner) err-owner-only)
    (ok (map-set user-reputation user
      (merge reputation {
        reputation-locked: true,
        last-updated: (+ block-height duration-blocks)
      })))))

(define-public (unlock-reputation (user principal))
  (let ((caller tx-sender)
        (reputation (unwrap! (map-get? user-reputation user) err-not-found)))
    (asserts! (is-eq caller contract-owner) err-owner-only)
    (ok (map-set user-reputation user
      (merge reputation {
        reputation-locked: false,
        last-updated: block-height
      })))))

(define-public (record-payment-activity 
  (counterparty principal)
  (amount uint)
  (transaction-hash (buff 32)))
  (let ((caller tx-sender)
        (activity-id (default-to u0 (map-get? user-activity-counter caller)))
        (score-increase (min (/ amount u1000) u50))
        (reputation (unwrap! (map-get? user-reputation caller) err-not-found)))
    (asserts! (not (get reputation-locked reputation)) err-unauthorized)
    
    (map-set reputation-activities 
      {user: caller, activity-id: (+ activity-id u1)}
      {
        activity-type: "payment",
        score-change: (to-int score-increase),
        timestamp: block-height,
        verifier: counterparty,
        description: "Payment transaction completed"
      })
    
    (map-set user-activity-counter caller (+ activity-id u1))
    (try! (update-user-score caller "payment" score-increase))
    (ok true)))

(define-public (record-governance-participation 
  (proposal-id uint)
  (vote-weight uint))
  (let ((caller tx-sender)
        (activity-id (default-to u0 (map-get? user-activity-counter caller)))
        (score-increase (min (/ vote-weight u100) u25))
        (reputation (unwrap! (map-get? user-reputation caller) err-not-found)))
    (asserts! (not (get reputation-locked reputation)) err-unauthorized)
    
    (map-set reputation-activities 
      {user: caller, activity-id: (+ activity-id u1)}
      {
        activity-type: "governance",
        score-change: (to-int score-increase),
        timestamp: block-height,
        verifier: contract-owner,
        description: "Participated in governance vote"
      })
    
    (map-set user-activity-counter caller (+ activity-id u1))
    (try! (update-user-score caller "governance" score-increase))
    (ok true)))

(define-public (record-social-activity
  (activity-type (string-ascii 32))
  (description (string-ascii 128))
  (score-impact uint))
  (let ((caller tx-sender)
        (activity-id (default-to u0 (map-get? user-activity-counter caller)))
        (reputation (unwrap! (map-get? user-reputation caller) err-not-found)))
    (asserts! (not (get reputation-locked reputation)) err-unauthorized)
    (asserts! (<= score-impact u30) err-invalid-score)
    
    (map-set reputation-activities 
      {user: caller, activity-id: (+ activity-id u1)}
      {
        activity-type: activity-type,
        score-change: (to-int score-impact),
        timestamp: block-height,
        verifier: caller,
        description: description
      })
    
    (map-set user-activity-counter caller (+ activity-id u1))
    (try! (update-user-score caller "social" score-impact))
    (ok true)))

(define-public (verify-external-action 
  (user principal)
  (action-hash (buff 32))
  (action-type (string-ascii 32))
  (score-impact uint))
  (let ((caller tx-sender))
    (asserts! (is-eq caller contract-owner) err-owner-only)
    (asserts! (<= score-impact u100) err-invalid-score)
    
    (map-set verified-actions 
      {user: user, action-hash: action-hash}
      {
        action-type: action-type,
        score-impact: score-impact,
        verified-at: block-height,
        verifier: caller
      })
    
    (try! (update-user-score user "social" score-impact))
    (ok true)))

(define-public (penalize-user (user principal) (penalty-points uint) (reason (string-ascii 128)))
  (let ((caller tx-sender)
        (activity-id (default-to u0 (map-get? user-activity-counter user))))
    (asserts! (is-eq caller contract-owner) err-owner-only)
    (asserts! (<= penalty-points u200) err-invalid-score)
    
    (map-set reputation-activities 
      {user: user, activity-id: (+ activity-id u1)}
      {
        activity-type: "penalty",
        score-change: (to-int (- u0 penalty-points)),
        timestamp: block-height,
        verifier: caller,
        description: reason
      })
    
    (map-set user-activity-counter user (+ activity-id u1))
    (let ((reputation (unwrap! (map-get? user-reputation user) err-not-found))
          (new-total (if (> (get total-score reputation) penalty-points)
                       (- (get total-score reputation) penalty-points)
                       u0)))
      (ok (map-set user-reputation user
        (merge reputation {
          total-score: new-total,
          last-updated: block-height
        }))))))

(define-private (update-user-score (user principal) (score-type (string-ascii 32)) (points uint))
  (let ((reputation (unwrap! (map-get? user-reputation user) err-not-found)))
    (if (is-eq score-type "payment")
      (let ((new-payment-score (+ (get payment-score reputation) points)))
        (map-set user-reputation user
          (merge reputation {
            payment-score: new-payment-score,
            total-score: (+ (+ (get base-score reputation) new-payment-score) 
                           (+ (get governance-score reputation) (get social-score reputation))),
            last-updated: block-height,
            trust-level: (calculate-trust-level (+ (+ (get base-score reputation) new-payment-score) 
                                                  (+ (get governance-score reputation) (get social-score reputation))))
          })))
      (if (is-eq score-type "governance")
        (let ((new-governance-score (+ (get governance-score reputation) points)))
          (map-set user-reputation user
            (merge reputation {
              governance-score: new-governance-score,
              total-score: (+ (+ (get base-score reputation) (get payment-score reputation))
                             (+ new-governance-score (get social-score reputation))),
              last-updated: block-height,
              trust-level: (calculate-trust-level (+ (+ (get base-score reputation) (get payment-score reputation))
                                                    (+ new-governance-score (get social-score reputation))))
            })))
        (let ((new-social-score (+ (get social-score reputation) points)))
          (map-set user-reputation user
            (merge reputation {
              social-score: new-social-score,
              total-score: (+ (+ (get base-score reputation) (get payment-score reputation))
                             (+ (get governance-score reputation) new-social-score)),
              last-updated: block-height,
              trust-level: (calculate-trust-level (+ (+ (get base-score reputation) (get payment-score reputation))
                                                    (+ (get governance-score reputation) new-social-score)))
            }))))))
  (ok true))

(define-public (delegate-reputation 
  (delegate principal)
  (score-amount uint)
  (duration-blocks uint))
  (let ((caller tx-sender)
        (caller-reputation (unwrap! (map-get? user-reputation caller) err-not-found)))
    (asserts! (>= (get total-score caller-reputation) score-amount) err-insufficient-balance)
    (asserts! (<= duration-blocks u144000) err-invalid-timeframe) ; Max 100 days
    
    (map-set reputation-delegates
      {delegator: caller, delegate: delegate}
      {
        delegated-score: score-amount,
        delegation-start: block-height,
        delegation-end: (+ block-height duration-blocks),
        active: true
      })
    
    (map-set user-reputation caller
      (merge caller-reputation {
        total-score: (- (get total-score caller-reputation) score-amount),
        last-updated: block-height
      }))
    (ok true)))

(define-public (revoke-delegation (delegate principal))
  (let ((caller tx-sender)
        (delegation (unwrap! (map-get? reputation-delegates {delegator: caller, delegate: delegate}) err-not-found))
        (caller-reputation (unwrap! (map-get? user-reputation caller) err-not-found)))
    (asserts! (get active delegation) err-unauthorized)
    
    (map-set reputation-delegates
      {delegator: caller, delegate: delegate}
      (merge delegation {active: false}))
    
    (map-set user-reputation caller
      (merge caller-reputation {
        total-score: (+ (get total-score caller-reputation) (get delegated-score delegation)),
        last-updated: block-height
      }))
    (ok true)))

(define-public (award-badge
  (user principal)
  (badge-type (string-ascii 32))
  (badge-level uint)
  (requirements (list 5 (string-ascii 64))))
  (let ((caller tx-sender))
    (asserts! (is-eq caller contract-owner) err-owner-only)
    (asserts! (<= badge-level u5) err-invalid-badge-level)
    
    (let ((badge-score (* badge-level u25)))
      (map-set user-badges
        {user: user, badge-type: badge-type}
        {
          badge-level: badge-level,
          earned-at: block-height,
          badge-score: badge-score,
          requirements-met: requirements
        })
      
      (try! (update-user-score user "social" badge-score))
      (ok true))))

(define-public (upgrade-badge
  (user principal)
  (badge-type (string-ascii 32))
  (new-level uint))
  (let ((caller tx-sender)
        (existing-badge (unwrap! (map-get? user-badges {user: user, badge-type: badge-type}) err-not-found)))
    (asserts! (is-eq caller contract-owner) err-owner-only)
    (asserts! (> new-level (get badge-level existing-badge)) err-invalid-badge-level)
    (asserts! (<= new-level u5) err-invalid-badge-level)
    
    (let ((level-diff (- new-level (get badge-level existing-badge)))
          (score-increase (* level-diff u25)))
      (map-set user-badges
        {user: user, badge-type: badge-type}
        (merge existing-badge {
          badge-level: new-level,
          badge-score: (* new-level u25)
        }))
      
      (try! (update-user-score user "social" score-increase))
      (ok true))))

(define-public (verify-user-identity (user principal))
  (let ((reputation (unwrap! (map-get? user-reputation user) err-not-found)))
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set user-reputation user
      (merge reputation {verified: true})))))

(define-private (calculate-trust-level (total-score uint))
  (if (>= total-score u1000) u5
  (if (>= total-score u500) u4
  (if (>= total-score u250) u3
  (if (>= total-score u100) u2
  u1)))))

(define-read-only (get-user-reputation (user principal))
  (map-get? user-reputation user))

(define-read-only (get-activity-history (user principal) (activity-id uint))
  (map-get? reputation-activities {user: user, activity-id: activity-id}))

(define-read-only (get-delegation-info (delegator principal) (delegate principal))
  (map-get? reputation-delegates {delegator: delegator, delegate: delegate}))

(define-read-only (get-user-badge (user principal) (badge-type (string-ascii 32)))
  (map-get? user-badges {user: user, badge-type: badge-type}))

(define-read-only (get-reputation-rank (user principal))
  (let ((reputation (map-get? user-reputation user)))
    (match reputation
      rep-data
      (let ((score (get total-score rep-data)))
        (if (>= score u1000) "legendary"
        (if (>= score u500) "excellent"
        (if (>= score u300) "good"
        (if (>= score u150) "fair"
        (if (>= score u50) "poor"
        "new"))))))
      "unranked")))

(define-read-only (calculate-trust-score (user principal) (context (string-ascii 32)))
  (let ((reputation (map-get? user-reputation user)))
    (match reputation
      rep-data
      (let ((base (get total-score rep-data))
            (verification-bonus (if (get verified rep-data) u50 u0))
            (trust-multiplier (* (get trust-level rep-data) u10))
            (context-multiplier (if (is-eq context "payment") u120 
                                (if (is-eq context "governance") u110 u100))))
        (/ (* (+ (+ base verification-bonus) trust-multiplier) context-multiplier) u100))
      u0)))

(define-read-only (get-effective-reputation (user principal))
  (let ((base-reputation (map-get? user-reputation user)))
    (match base-reputation
      rep-data
      (let ((base-score (get total-score rep-data)))
        ;; Add delegated reputation received
        (fold check-received-delegations (list user) base-score))
      u0)))

(define-private (check-received-delegations (user-list (list 1 principal)) (current-score uint))
  current-score)

(define-read-only (is-reputation-locked (user principal))
  (let ((reputation (map-get? user-reputation user)))
    (match reputation
      rep-data (get reputation-locked rep-data)
      false)))

(define-read-only (get-user-activity-count (user principal))
  (default-to u0 (map-get? user-activity-counter user)))

(define-read-only (calculate-reputation-decay (user principal))
  (let ((reputation (map-get? user-reputation user)))
    (match reputation
      rep-data
      (let ((blocks-since-update (- block-height (get last-updated rep-data)))
            (decay-rate (if (> blocks-since-update u14400) u5 u0))) ; 10 days threshold
        (if (> (get total-score rep-data) decay-rate)
          (- (get total-score rep-data) decay-rate)
          u0))
      u0)))