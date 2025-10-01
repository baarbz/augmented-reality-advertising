;; title: ar-billboard
;; version: 1.0.0
;; summary: Location-based AR advertising platform with token rewards
;; description: Place location-based AR advertisements, verify user engagement with AR content, distribute earnings to users who view ads, manage spatial advertising rights, and track campaign effectiveness metrics

;; constants
(define-constant CONTRACT_OWNER tx-sender)
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_CAMPAIGN_NOT_FOUND (err u101))
(define-constant ERR_INVALID_LOCATION (err u102))
(define-constant ERR_INSUFFICIENT_BUDGET (err u103))
(define-constant ERR_CAMPAIGN_EXPIRED (err u104))
(define-constant ERR_ALREADY_VIEWED (err u105))
(define-constant ERR_INVALID_ENGAGEMENT (err u106))

(define-constant MIN_CAMPAIGN_BUDGET u100)
(define-constant USER_REWARD_PERCENT u60)
(define-constant PLATFORM_FEE_PERCENT u25)
(define-constant BASE_VIEW_REWARD u10)
(define-constant PREMIUM_LOCATION_MULTIPLIER u2)
(define-constant ENGAGEMENT_BONUS_MULTIPLIER u3)

;; data vars
(define-data-var total-campaigns uint u0)
(define-data-var total-views uint u0)
(define-data-var total-rewards-paid uint u0)
(define-data-var platform-revenue uint u0)
(define-data-var next-campaign-id uint u1)

;; data maps
(define-map ar-campaigns
    { campaign-id: uint }
    {
        advertiser: principal,
        campaign-name: (string-ascii 50),
        ad-content-hash: (string-ascii 64),
        target-latitude: int,
        target-longitude: int,
        radius: uint,
        budget: uint,
        spent: uint,
        reward-per-view: uint,
        start-time: uint,
        end-time: uint,
        is-active: bool,
        total-views: uint,
        total-engagements: uint,
        category: (string-ascii 20)
    }
)

(define-map ad-views
    { campaign-id: uint, viewer: principal }
    {
        view-time: uint,
        view-latitude: int,
        view-longitude: int,
        engagement-duration: uint,
        interaction-score: uint,
        reward-earned: uint
    }
)

(define-map user-earnings
    { user: principal }
    {
        total-earned: uint,
        total-views: uint,
        pending-rewards: uint,
        preferred-categories: (string-ascii 100),
        location-bonuses: uint
    }
)

(define-map location-zones
    { lat-zone: int, lng-zone: int }
    {
        zone-type: (string-ascii 20),
        premium-multiplier: uint,
        active-campaigns: uint,
        total-views: uint
    }
)

(define-map campaign-analytics
    { campaign-id: uint }
    {
        unique-viewers: uint,
        average-engagement: uint,
        conversion-rate: uint,
        effectiveness-score: uint,
        geographic-reach: uint
    }
)

;; public functions

;; Create AR advertising campaign
(define-public (create-campaign (campaign-name (string-ascii 50)) (ad-content-hash (string-ascii 64)) (target-latitude int) (target-longitude int) (radius uint) (budget uint) (reward-per-view uint) (duration uint) (category (string-ascii 20)))
    (let
        (
            (campaign-id (var-get next-campaign-id))
            (end-time (+ stacks-block-height duration))
        )
        (asserts! (>= budget MIN_CAMPAIGN_BUDGET) ERR_INSUFFICIENT_BUDGET)
        (asserts! (and (>= target-latitude -900000) (<= target-latitude 900000)) ERR_INVALID_LOCATION)
        (asserts! (and (>= target-longitude -1800000) (<= target-longitude 1800000)) ERR_INVALID_LOCATION)
        (asserts! (> radius u0) ERR_INVALID_LOCATION)
        (asserts! (>= reward-per-view u5) ERR_INSUFFICIENT_BUDGET)
        
        ;; Create campaign
        (map-set ar-campaigns
            { campaign-id: campaign-id }
            {
                advertiser: tx-sender,
                campaign-name: campaign-name,
                ad-content-hash: ad-content-hash,
                target-latitude: target-latitude,
                target-longitude: target-longitude,
                radius: radius,
                budget: budget,
                spent: u0,
                reward-per-view: reward-per-view,
                start-time: stacks-block-height,
                end-time: end-time,
                is-active: true,
                total-views: u0,
                total-engagements: u0,
                category: category
            }
        )
        
        ;; Initialize campaign analytics
        (map-set campaign-analytics
            { campaign-id: campaign-id }
            {
                unique-viewers: u0,
                average-engagement: u0,
                conversion-rate: u0,
                effectiveness-score: u0,
                geographic-reach: u0
            }
        )
        
        ;; Update location zone
        (update-location-zone target-latitude target-longitude)
        
        ;; Update global counters
        (var-set total-campaigns (+ (var-get total-campaigns) u1))
        (var-set next-campaign-id (+ campaign-id u1))
        
        (ok campaign-id)
    )
)

;; View AR advertisement and earn rewards
(define-public (view-ad (campaign-id uint) (view-latitude int) (view-longitude int) (engagement-duration uint) (interaction-score uint))
    (let
        (
            (campaign (unwrap! (map-get? ar-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
            (distance (calculate-distance (get target-latitude campaign) (get target-longitude campaign) view-latitude view-longitude))
            (user-data (default-to {
                total-earned: u0,
                total-views: u0,
                pending-rewards: u0,
                preferred-categories: "",
                location-bonuses: u0
            } (map-get? user-earnings { user: tx-sender })))
        )
        (asserts! (get is-active campaign) ERR_CAMPAIGN_EXPIRED)
        (asserts! (< stacks-block-height (get end-time campaign)) ERR_CAMPAIGN_EXPIRED)
        (asserts! (<= (to-uint distance) (get radius campaign)) ERR_INVALID_LOCATION)
        (asserts! (is-none (map-get? ad-views { campaign-id: campaign-id, viewer: tx-sender })) ERR_ALREADY_VIEWED)
        (asserts! (<= interaction-score u100) ERR_INVALID_ENGAGEMENT)
        
        (let
            (
                (base-reward (get reward-per-view campaign))
                (engagement-bonus (if (>= engagement-duration u30) (/ (* base-reward ENGAGEMENT_BONUS_MULTIPLIER) u10) u0))
                (location-bonus (calculate-location-bonus view-latitude view-longitude))
                (total-reward (+ base-reward engagement-bonus location-bonus))
                (remaining-budget (- (get budget campaign) (get spent campaign)))
            )
            (asserts! (>= remaining-budget total-reward) ERR_INSUFFICIENT_BUDGET)
            
            ;; Record ad view
            (map-set ad-views
                { campaign-id: campaign-id, viewer: tx-sender }
                {
                    view-time: stacks-block-height,
                    view-latitude: view-latitude,
                    view-longitude: view-longitude,
                    engagement-duration: engagement-duration,
                    interaction-score: interaction-score,
                    reward-earned: total-reward
                }
            )
            
            ;; Update campaign statistics
            (map-set ar-campaigns
                { campaign-id: campaign-id }
                (merge campaign {
                    spent: (+ (get spent campaign) total-reward),
                    total-views: (+ (get total-views campaign) u1),
                    total-engagements: (if (>= engagement-duration u10) (+ (get total-engagements campaign) u1) (get total-engagements campaign))
                })
            )
            
            ;; Update user earnings
            (map-set user-earnings
                { user: tx-sender }
                (merge user-data {
                    total-earned: (+ (get total-earned user-data) total-reward),
                    total-views: (+ (get total-views user-data) u1),
                    pending-rewards: (+ (get pending-rewards user-data) total-reward),
                    location-bonuses: (+ (get location-bonuses user-data) location-bonus)
                })
            )
            
            ;; Update global statistics
            (var-set total-views (+ (var-get total-views) u1))
            (var-set total-rewards-paid (+ (var-get total-rewards-paid) total-reward))
            
            (ok total-reward)
        )
    )
)

;; Claim accumulated rewards
(define-public (claim-rewards)
    (let
        (
            (user-data (unwrap! (map-get? user-earnings { user: tx-sender }) ERR_UNAUTHORIZED))
            (pending (get pending-rewards user-data))
        )
        (asserts! (> pending u0) ERR_INSUFFICIENT_BUDGET)
        
        ;; Reset pending rewards
        (map-set user-earnings
            { user: tx-sender }
            (merge user-data { pending-rewards: u0 })
        )
        
        (ok pending)
    )
)

;; Update campaign status
(define-public (update-campaign-status (campaign-id uint) (is-active bool))
    (let
        (
            (campaign (unwrap! (map-get? ar-campaigns { campaign-id: campaign-id }) ERR_CAMPAIGN_NOT_FOUND))
        )
        (asserts! (is-eq (get advertiser campaign) tx-sender) ERR_UNAUTHORIZED)
        
        (map-set ar-campaigns
            { campaign-id: campaign-id }
            (merge campaign { is-active: is-active })
        )
        
        (ok true)
    )
)

;; Set user ad preferences
(define-public (set-ad-preferences (preferred-categories (string-ascii 100)))
    (let
        (
            (user-data (default-to {
                total-earned: u0,
                total-views: u0,
                pending-rewards: u0,
                preferred-categories: "",
                location-bonuses: u0
            } (map-get? user-earnings { user: tx-sender })))
        )
        (map-set user-earnings
            { user: tx-sender }
            (merge user-data { preferred-categories: preferred-categories })
        )
        
        (ok true)
    )
)

;; read only functions

;; Get campaign information
(define-read-only (get-campaign (campaign-id uint))
    (map-get? ar-campaigns { campaign-id: campaign-id })
)

;; Get user earnings
(define-read-only (get-user-earnings (user principal))
    (map-get? user-earnings { user: user })
)

;; Get ad view details
(define-read-only (get-ad-view (campaign-id uint) (viewer principal))
    (map-get? ad-views { campaign-id: campaign-id, viewer: viewer })
)

;; Get platform statistics
(define-read-only (get-platform-stats)
    {
        total-campaigns: (var-get total-campaigns),
        total-views: (var-get total-views),
        total-rewards-paid: (var-get total-rewards-paid),
        platform-revenue: (var-get platform-revenue)
    }
)

;; Get campaign analytics
(define-read-only (get-campaign-analytics (campaign-id uint))
    (map-get? campaign-analytics { campaign-id: campaign-id })
)

;; Check if campaign is active
(define-read-only (is-campaign-active (campaign-id uint))
    (match (map-get? ar-campaigns { campaign-id: campaign-id })
        campaign (and (get is-active campaign) (< stacks-block-height (get end-time campaign)))
        false
    )
)

;; Get location zone info
(define-read-only (get-location-zone (lat-zone int) (lng-zone int))
    (map-get? location-zones { lat-zone: lat-zone, lng-zone: lng-zone })
)

;; private functions

;; Calculate distance between two points (simplified)
(define-private (calculate-distance (lat1 int) (lng1 int) (lat2 int) (lng2 int))
    (let
        (
            (lat-diff (if (>= lat1 lat2) (- lat1 lat2) (- lat2 lat1)))
            (lng-diff (if (>= lng1 lng2) (- lng1 lng2) (- lng2 lng1)))
        )
        (+ lat-diff lng-diff) ;; Simplified Manhattan distance
    )
)

;; Calculate location bonus based on zone premium
(define-private (calculate-location-bonus (lat int) (lng int))
    (let
        (
            (lat-zone (/ lat 10000))
            (lng-zone (/ lng 10000))
            (zone-data (default-to {
                zone-type: "standard",
                premium-multiplier: u1,
                active-campaigns: u0,
                total-views: u0
            } (map-get? location-zones { lat-zone: lat-zone, lng-zone: lng-zone })))
        )
        (* BASE_VIEW_REWARD (get premium-multiplier zone-data))
    )
)

;; Update location zone data
(define-private (update-location-zone (lat int) (lng int))
    (let
        (
            (lat-zone (/ lat 10000))
            (lng-zone (/ lng 10000))
            (current-zone (default-to {
                zone-type: "standard",
                premium-multiplier: u1,
                active-campaigns: u0,
                total-views: u0
            } (map-get? location-zones { lat-zone: lat-zone, lng-zone: lng-zone })))
        )
        (map-set location-zones
            { lat-zone: lat-zone, lng-zone: lng-zone }
            (merge current-zone {
                active-campaigns: (+ (get active-campaigns current-zone) u1)
            })
        )
    )
)
