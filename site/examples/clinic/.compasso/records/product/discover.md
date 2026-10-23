# Discover · Clinic Booking · 2026-10-26
Approved by @rita · Run by @compasso

## Findings
- security: The appointment reason is free text and may hold health details → Optional, staff-only, every read logged
- security: Booking without a confirmed email lets anyone fill the calendar → A held booking expires after 15 minutes unless confirmed

## Decisions
- Email reminders in the MVP, SMS after it (@rita, 2026-10-26)
- Patients never create an account: a confirmed email is enough (@rita, 2026-10-26)
- Assumed: Data stays in an EU region

## Takeaways
- Reception books about 70 appointments a day by phone

## Constraints
- Live before the January campaign

## Missing points
- Will therapists share rooms? It would limit slots (open)
