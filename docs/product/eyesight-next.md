# Fifteen directions for Eyesight

This iteration ships native motion history, a signed opening difference view, richer pixel geometry, a single person scene guard, calibration ownership, detection alerts, optional sound cues and live practice feedback. Blink mirror, camera setup and coverage are now implemented in Eyesight 2.7. The remaining directions describe future work. They are proposals, not claims that the webcam can diagnose dry eye, measure the retina or identify a person.

Blink mirror now records a ten second native observation and offers explicit replay of the latest detected bilateral blink. Counts and valid exposure use original measurements; missing time stays unmeasured and reduced motion shows a static trace.

A near and far practice could alternate between a real nearby object and a distant object chosen by the user. The timer would guide the change while stating that eyelid landmarks cannot verify where someone focuses.

A gentle pursuit game could move a target through a slow path with adjustable speed and size. It would require a separately validated gaze model before offering tracking accuracy or motion scores; the current eyelid tracker alone cannot measure gaze.

An optional quiet rest could guide a short, comfortable eyes closed pause. It would work without the camera and use sound only when requested, with an obvious way to stop.

A screen exit ritual could turn a completed work interval into a brief look away and movement break. The user would choose the interval, with Later and Skip preserved and no break debt after sleep or lock.

Camera setup now checks the camera stream, single person scene, both measured contours, fresh samples and eye reference. Its framing SVG uses measured geometry without exposing a camera image or claiming diagnostic accuracy.

A glasses and lighting check could compare short observations under the user’s current lighting. It would report landmark loss and sample coverage; any reflection detection would need its own validated image measurement.

A comfort journal could pair optional user entered dryness or irritation notes with daily observations. It would keep subjective comfort separate from measured blink activity and avoid treating a change in blink rate as a diagnosis.

Manual local profiles could let household members explicitly choose their own history and preferences. Profiles would require isolated storage, export and deletion before launch. Face recognition would not choose a profile or infer identity.

Session context labels could distinguish reading, coding, calls and other work chosen by the user. Aggregate comparisons would expose observed time and missing coverage so short sessions do not appear more reliable than they are.

Camera coverage now shows five minutes of native tracking states, interruptions and missing time with actual valid exposure. It remains bounded in memory and saves no images, face templates or identity data.

A closure timing profile could summarize detected closure durations and bilateral versus unilateral events. It would show sample cadence and exclude long missing intervals rather than turn uncertainty into precise millisecond claims.

Repeatable scan comparisons could compare two explicitly started sessions with the same camera and adequate valid exposure. Saved reports would contain summaries only, and explain how lighting, pose and calibration affect differences.

A personal practice plan could use chosen routines, comfortable time goals and completion milestones. It would reward returning and taking breaks rather than accumulating camera time or competing on blink counts.

An examination companion could produce a user controlled summary of symptoms, observation coverage and aggregate patterns to discuss at an appointment. A retinal scan, eye pressure measurement and visual acuity examination remain outside this webcam app. The American Society of Retina Specialists describes the dedicated optics and imaging used for retinal examination at https://www.asrs.org/patients/advanced-retinal-imaging.
