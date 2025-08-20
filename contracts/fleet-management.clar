;; Fleet Management Contract
;; Manages autonomous vehicle fleet coordination and operations

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-VEHICLE-NOT-FOUND (err u101))
(define-constant ERR-VEHICLE-ALREADY-EXISTS (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-VEHICLE-IN-USE (err u104))
(define-constant ERR-INVALID-COORDINATES (err u105))

;; Vehicle Status Types
(define-constant STATUS-AVAILABLE u1)
(define-constant STATUS-IN-TRANSIT u2)
(define-constant STATUS-MAINTENANCE u3)
(define-constant STATUS-OFFLINE u4)

;; Data Variables
(define-data-var total-vehicles uint u0)
(define-data-var active-vehicles uint u0)

;; Data Maps
(define-map vehicles
  { vehicle-id: (string-ascii 20) }
  {
    owner: principal,
    status: uint,
    latitude: int,
    longitude: int,
    battery-level: uint,
    last-updated: uint,
    total-distance: uint,
    maintenance-due: uint
  }
)

(define-map vehicle-assignments
  { vehicle-id: (string-ascii 20) }
  {
    route-id: (string-ascii 20),
    passenger-count: uint,
    destination-lat: int,
    destination-lng: int,
    estimated-arrival: uint
  }
)

(define-map authorized-operators
  { operator: principal }
  { authorized: bool }
)

;; Authorization Functions
(define-private (is-authorized (caller principal))
  (or
    (is-eq caller CONTRACT-OWNER)
    (default-to false (get authorized (map-get? authorized-operators { operator: caller })))
  )
)

;; Vehicle Registration
(define-public (register-vehicle (vehicle-id (string-ascii 20)) (initial-lat int) (initial-lng int))
  (let ((caller tx-sender))
    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    (asserts! (is-none (map-get? vehicles { vehicle-id: vehicle-id })) ERR-VEHICLE-ALREADY-EXISTS)
    (asserts! (and (>= initial-lat -90000000) (<= initial-lat 90000000)) ERR-INVALID-COORDINATES)
    (asserts! (and (>= initial-lng -180000000) (<= initial-lng 180000000)) ERR-INVALID-COORDINATES)

    (map-set vehicles
      { vehicle-id: vehicle-id }
      {
        owner: caller,
        status: STATUS-AVAILABLE,
        latitude: initial-lat,
        longitude: initial-lng,
        battery-level: u100,
        last-updated: block-height,
        total-distance: u0,
        maintenance-due: (+ block-height u1000)
      }
    )

    (var-set total-vehicles (+ (var-get total-vehicles) u1))
    (var-set active-vehicles (+ (var-get active-vehicles) u1))
    (ok vehicle-id)
  )
)

;; Update Vehicle Status
(define-public (update-vehicle-status (vehicle-id (string-ascii 20)) (new-status uint) (lat int) (lng int) (battery uint))
  (let ((caller tx-sender)
        (vehicle-data (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-VEHICLE-NOT-FOUND)))

    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-status u1) (<= new-status u4)) ERR-INVALID-STATUS)
    (asserts! (and (>= lat -90000000) (<= lat 90000000)) ERR-INVALID-COORDINATES)
    (asserts! (and (>= lng -180000000) (<= lng 180000000)) ERR-INVALID-COORDINATES)
    (asserts! (<= battery u100) ERR-INVALID-STATUS)

    (map-set vehicles
      { vehicle-id: vehicle-id }
      (merge vehicle-data {
        status: new-status,
        latitude: lat,
        longitude: lng,
        battery-level: battery,
        last-updated: block-height
      })
    )
    (ok true)
  )
)

;; Assign Vehicle to Route
(define-public (assign-vehicle-route (vehicle-id (string-ascii 20)) (route-id (string-ascii 20)) (dest-lat int) (dest-lng int) (passengers uint))
  (let ((caller tx-sender)
        (vehicle-data (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-VEHICLE-NOT-FOUND)))

    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status vehicle-data) STATUS-AVAILABLE) ERR-VEHICLE-IN-USE)
    (asserts! (and (>= dest-lat -90000000) (<= dest-lat 90000000)) ERR-INVALID-COORDINATES)
    (asserts! (and (>= dest-lng -180000000) (<= dest-lng 180000000)) ERR-INVALID-COORDINATES)

    ;; Update vehicle status to in-transit
    (map-set vehicles
      { vehicle-id: vehicle-id }
      (merge vehicle-data { status: STATUS-IN-TRANSIT })
    )

    ;; Create route assignment
    (map-set vehicle-assignments
      { vehicle-id: vehicle-id }
      {
        route-id: route-id,
        passenger-count: passengers,
        destination-lat: dest-lat,
        destination-lng: dest-lng,
        estimated-arrival: (+ block-height u50)
      }
    )
    (ok true)
  )
)

;; Complete Route Assignment
(define-public (complete-route (vehicle-id (string-ascii 20)) (distance-traveled uint))
  (let ((caller tx-sender)
        (vehicle-data (unwrap! (map-get? vehicles { vehicle-id: vehicle-id }) ERR-VEHICLE-NOT-FOUND)))

    (asserts! (is-authorized caller) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status vehicle-data) STATUS-IN-TRANSIT) ERR-INVALID-STATUS)

    ;; Update vehicle status back to available and add distance
    (map-set vehicles
      { vehicle-id: vehicle-id }
      (merge vehicle-data {
        status: STATUS-AVAILABLE,
        total-distance: (+ (get total-distance vehicle-data) distance-traveled),
        last-updated: block-height
      })
    )

    ;; Remove route assignment
    (map-delete vehicle-assignments { vehicle-id: vehicle-id })
    (ok true)
  )
)

;; Authorize Operator
(define-public (authorize-operator (operator principal))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (map-set authorized-operators { operator: operator } { authorized: true })
    (ok true)
  )
)

;; Read-only Functions
(define-read-only (get-vehicle-info (vehicle-id (string-ascii 20)))
  (map-get? vehicles { vehicle-id: vehicle-id })
)

(define-read-only (get-vehicle-assignment (vehicle-id (string-ascii 20)))
  (map-get? vehicle-assignments { vehicle-id: vehicle-id })
)

(define-read-only (get-fleet-stats)
  {
    total-vehicles: (var-get total-vehicles),
    active-vehicles: (var-get active-vehicles)
  }
)

(define-read-only (is-operator-authorized (operator principal))
  (default-to false (get authorized (map-get? authorized-operators { operator: operator })))
)
