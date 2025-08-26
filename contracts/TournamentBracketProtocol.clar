;; TournamentBracket Protocol (no recursion; even-size bracket; lazy round building)

(define-fungible-token tournament-token)

;; Errors
(define-constant err-not-organizer (err u100))
(define-constant err-invalid-tournament (err u101))
(define-constant err-tournament-started (err u102))
(define-constant err-tournament-not-started (err u103))
(define-constant err-already-registered (err u104))
(define-constant err-registration-closed (err u105))
(define-constant err-insufficient-participants (err u106))
(define-constant err-not-participant (err u107))
(define-constant err-match-already-resolved (err u108))
(define-constant err-invalid-match (err u109))
(define-constant err-tournament-finished (err u110))
(define-constant err-invalid-entry-fee (err u111))
(define-constant err-max-participants-reached (err u112))
(define-constant err-invalid-winner (err u114))
(define-constant err-max-participants-must-be-even (err u115))
(define-constant err-payment-failed (err u116))

;; Status
(define-constant status-pending u0)
(define-constant status-active u1)
(define-constant status-completed u2)

;; Data Vars
(define-data-var tournament-counter uint u0)
(define-data-var total-prize-pool uint u0)

;; Tournaments
(define-map tournaments uint {
  organizer: principal,
  name: (string-ascii 50),
  entry-fee: uint,
  max-participants: uint,
  current-participants: uint,
  status: uint,
  prize-pool: uint,
  winner: (optional principal),
  created-at: uint
})

;; Registrations
(define-map tournament-participants {tournament-id: uint, participant: principal} bool)
(define-map participant-list {tournament-id: uint, index: uint} principal)

;; Matches
(define-map match-results {tournament-id: uint, round: uint, match-id: uint} {
  participant1: principal,
  participant2: principal,
  winner: (optional principal),
  resolved: bool
})

;; Rounds
(define-map tournament-rounds uint uint)

;; Per-round counts to avoid loops/recursion
(define-map round-match-counts {tournament-id: uint, round: uint} uint)
(define-map round-resolved-counts {tournament-id: uint, round: uint} uint)

;; --------------- Helpers ---------------

(define-private (get-or-zero (opt-val (optional uint)))
  (default-to u0 opt-val))

(define-private (incr-round-match-count (tid uint) (rnd uint))
  (let ((key {tournament-id: tid, round: rnd})
        (cur (get-or-zero (map-get? round-match-counts key))))
    (map-set round-match-counts key (+ cur u1))))

(define-private (incr-round-resolved-count (tid uint) (rnd uint))
  (let ((key {tournament-id: tid, round: rnd})
        (cur (get-or-zero (map-get? round-resolved-counts key))))
    (map-set round-resolved-counts key (+ cur u1))))

(define-private (round-complete? (tid uint) (rnd uint))
  (let ((key {tournament-id: tid, round: rnd})
        (made (get-or-zero (map-get? round-match-counts key)))
        (done (get-or-zero (map-get? round-resolved-counts key))))
    (and (> made u0) (is-eq made done))))

(define-private (get-participant (tid uint) (idx uint))
  (unwrap-panic (map-get? participant-list {tournament-id: tid, index: idx})))

;; Safe division function
(define-private (safe-divide (a uint) (b uint))
  (if (> b u0) (/ a b) u0))

;; --------------- Public Functions ---------------

(define-public (create-tournament (name (string-ascii 50)) (entry-fee uint) (max-participants uint))
  (let ((tid (+ (var-get tournament-counter) u1)))
    (begin
      (asserts! (> max-participants u1) err-insufficient-participants)
      (asserts! (is-eq (mod max-participants u2) u0) err-max-participants-must-be-even)
      
      (map-set tournaments tid {
        organizer: tx-sender,
        name: name,
        entry-fee: entry-fee,
        max-participants: max-participants,
        current-participants: u0,
        status: status-pending,
        prize-pool: u0,
        winner: none,
        created-at: u0
      })
      (map-set tournament-rounds tid u0)
      (var-set tournament-counter tid)

      ;; Handle organizer auto-registration if there's an entry fee
      (if (> entry-fee u0)
        (begin
          (try! (stx-transfer? entry-fee tx-sender (as-contract tx-sender)))
          (var-set total-prize-pool (+ (var-get total-prize-pool) entry-fee))
          (map-set tournament-participants {tournament-id: tid, participant: tx-sender} true)
          (map-set participant-list {tournament-id: tid, index: u0} tx-sender)
          (map-set tournaments tid
            (merge (unwrap-panic (map-get? tournaments tid))
              {current-participants: u1, prize-pool: entry-fee}))
          (ok {tournament-id: tid, message: "Tournament created with organizer as first participant"}))
        (ok {tournament-id: tid, message: "Tournament created successfully"})))))


   

(define-read-only (get-tournament-info (tournament-id uint))
  (ok (map-get? tournaments tournament-id)))

(define-read-only (get-tournament-status (tournament-id uint))
  (match (map-get? tournaments tournament-id)
    tournament (ok (get status tournament))
    (ok u0)))

(define-read-only (get-total-tournaments)
  (ok (var-get tournament-counter)))

(define-read-only (is-participant (tournament-id uint) (participant principal))
  (ok (default-to false (map-get? tournament-participants {tournament-id: tournament-id, participant: participant}))))

(define-read-only (get-tournament-prize-pool (tournament-id uint))
  (match (map-get? tournaments tournament-id)
    tournament (ok (get prize-pool tournament))
    (ok u0)))

(define-read-only (get-match-result (tournament-id uint) (round uint) (match-id uint))
  (ok (map-get? match-results {tournament-id: tournament-id, round: round, match-id: match-id})))

(define-read-only (get-current-round (tournament-id uint))
  (ok (default-to u0 (map-get? tournament-rounds tournament-id))))

(define-read-only (get-round-stats (tournament-id uint) (round uint))
  (ok {
    matches-created: (get-or-zero (map-get? round-match-counts {tournament-id: tournament-id, round: round})),
    matches-resolved: (get-or-zero (map-get? round-resolved-counts {tournament-id: tournament-id, round: round}))
  }))

(define-read-only (get-participant-by-index (tournament-id uint) (index uint))
  (ok (map-get? participant-list {tournament-id: tournament-id, index: index})))

(define-read-only (get-total-prize-pool)
  (ok (var-get total-prize-pool)))