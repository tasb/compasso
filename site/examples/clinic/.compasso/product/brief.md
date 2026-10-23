# Clinic Booking

## Problem
A physiotherapy clinic with 6 therapists books every appointment by phone. Reception spends about 3 hours a day on calls, patients can only book during opening hours, and 1 in 8 appointments is missed because nobody reminds the patient.

## Users
- **Patients**: book, move or cancel an appointment at any hour, from a phone.
- **Reception**: sees the day at a glance, books for patients who still call, handles changes.
- **Therapists**: set their working hours and see who comes next.
- **Clinic owner**: wants fewer missed appointments and less time on the phone.

## Outcomes
- At least 60% of appointments booked online within 3 months.
- Missed appointments down from 12% to under 5%.
- Reception time on the phone cut by half.

## The MVP must prove
- Patients book a real free slot online, without calling, and never into a double booking.
- A reminder email the day before reduces missed appointments.
- Reception can run a full day from the staff calendar alone.

## Constraints
- Live before the clinic's January campaign: 3 sprints of 2 weeks.
- Patient data is health data under the GDPR: stored in the EU, access logged.
- Works on any phone browser; no app to install.

## Risks
- Patients who book and never come: a booking needs a confirmed email.
- Health data: the appointment reason is free text and may hold clinical details. Security asked to keep it optional and visible to staff only.
- The email provider's sending limits during the January campaign.

## Sources
- Interview with the clinic owner and reception (notes.md).
- 3 tracker issues opened by the owner: online booking, reminders, waiting list.
- A clickable prototype of the patient booking screens.
