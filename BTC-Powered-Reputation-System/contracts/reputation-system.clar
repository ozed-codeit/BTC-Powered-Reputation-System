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