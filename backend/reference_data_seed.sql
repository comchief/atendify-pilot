-- Real reference data: the agency directory, municipal officer roster, role
-- permission templates, demo venues/advertisement price list, and the one
-- seeded watchlist entry — sourced directly from the matching arrays in
-- atendify.html (ATD_AGENCY_SEED / ATD_MUNI_USER_SEED / ADMIN_ROLE_SEED /
-- venues / adItems / watchlist). None of this can be seeded by the app
-- itself once RLS is enforced (those client-side writes always fail — see
-- chat), so it's all loaded here instead, the same way staff_invites
-- already is. Safe to re-run any time; every insert is on-conflict-update.
insert into public.kv_store (key, value) values
  ('agency:1', '{"id": 1, "name": "Kingston & St. Andrew Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 1, "parish": "Kingston", "jurisdictionParishes": ["Kingston", "St. Andrew"], "contact": "Andrea Powell", "phone": "876-922-0140", "email": "kmc.admin@gov.jm", "status": "Active", "created": "2026-01-14", "roleId": 1, "appFeeAnnual": 2500, "appFeeSpecial": 3500, "platformFee": 15000, "platformBilling": "Monthly"}'::jsonb),
  ('agency:2', '{"id": 2, "name": "St. Mary Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 4, "parish": "St. Mary", "jurisdictionParishes": ["St. Mary"], "contact": "Marlon Reid", "phone": "876-465-2210", "email": "stmary.admin@gov.jm", "status": "Active", "created": "2026-02-02", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 120000, "platformBilling": "Annual"}'::jsonb),
  ('agency:3', '{"id": 3, "name": "St. James Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 7, "parish": "St. James", "jurisdictionParishes": ["St. James"], "contact": "Kerry-Ann Blake", "phone": "876-952-1873", "email": "mobay.admin@gov.jm", "status": "Suspended", "created": "2026-03-10", "roleId": 2, "appFeeAnnual": 2500, "appFeeSpecial": 4000, "platformFee": 15000, "platformBilling": "Monthly"}'::jsonb),
  ('agency:4', '{"id": 4, "name": "Manchester Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 11, "parish": "Manchester", "jurisdictionParishes": ["Manchester"], "contact": "Devon Hylton", "phone": "876-962-4405", "email": "manchester.admin@gov.jm", "status": "Active", "created": "2026-04-22", "roleId": 3, "appFeeAnnual": 1800, "appFeeSpecial": 2800, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:5', '{"id": 5, "name": "Jamaica Constabulary Force \u2014 Noise Abatement Unit", "type": "JCF", "linkedMuniId": 1, "parish": "Kingston", "contact": "Insp. Rohan Blake", "phone": "876-922-9911", "email": "noise.abatement@jcf.gov.jm", "status": "Active", "created": "2026-05-06", "roleId": 2, "appFeeAnnual": 0, "appFeeSpecial": 0, "platformFee": 40000, "platformBilling": "Annual"}'::jsonb),
  ('agency:6', '{"id": 6, "name": "Jamaica Fire Brigade", "type": "JFB", "linkedMuniId": 1, "parish": "St. Andrew", "contact": "Supt. Claudette Morris", "phone": "876-926-2323", "email": "permits@jfb.gov.jm", "status": "Active", "created": "2026-05-20", "roleId": 2, "appFeeAnnual": 0, "appFeeSpecial": 0, "platformFee": 40000, "platformBilling": "Annual"}'::jsonb),
  ('agency:7', '{"id": 7, "name": "JCF \u2014 St. Mary Division", "type": "JCF", "linkedMuniId": 2, "parish": "St. Mary", "contact": "Insp. Paula Grant", "phone": "876-994-2500", "email": "stmary.division@jcf.gov.jm", "status": "Active", "created": "2026-06-01", "roleId": 2, "appFeeAnnual": 0, "appFeeSpecial": 0, "platformFee": 40000, "platformBilling": "Annual"}'::jsonb),
  ('agency:8', '{"id": 8, "name": "Portmore Municipal Council", "type": "Municipal Corporation", "muniNumber": 14, "parish": "Portmore", "jurisdictionParishes": ["Portmore"], "contact": "Sasha-Kay Reid", "phone": "876-988-7300", "email": "portmore.admin@gov.jm", "status": "Active", "created": "2026-08-01", "roleId": 2, "appFeeAnnual": 2200, "appFeeSpecial": 3200, "platformFee": 15000, "platformBilling": "Monthly"}'::jsonb),
  ('agency:9', '{"id": 9, "name": "St. Thomas Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 2, "parish": "St. Thomas", "jurisdictionParishes": ["St. Thomas"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:10', '{"id": 10, "name": "Portland Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 3, "parish": "Portland", "jurisdictionParishes": ["Portland"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:11', '{"id": 11, "name": "St. Ann Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 5, "parish": "St. Ann", "jurisdictionParishes": ["St. Ann"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:12', '{"id": 12, "name": "Trelawny Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 6, "parish": "Trelawny", "jurisdictionParishes": ["Trelawny"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:13', '{"id": 13, "name": "Hanover Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 8, "parish": "Hanover", "jurisdictionParishes": ["Hanover"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:14', '{"id": 14, "name": "Westmoreland Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 9, "parish": "Westmoreland", "jurisdictionParishes": ["Westmoreland"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:15', '{"id": 15, "name": "St. Elizabeth Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 10, "parish": "St. Elizabeth", "jurisdictionParishes": ["St. Elizabeth"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:16', '{"id": 16, "name": "Clarendon Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 12, "parish": "Clarendon", "jurisdictionParishes": ["Clarendon"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb),
  ('agency:17', '{"id": 17, "name": "St. Catherine Municipal Corporation", "type": "Municipal Corporation", "muniNumber": 13, "parish": "St. Catherine", "jurisdictionParishes": ["St. Catherine"], "contact": "", "phone": "", "email": "", "status": "Active", "created": "2026-08-23", "roleId": 2, "appFeeAnnual": 2000, "appFeeSpecial": 3000, "platformFee": 100000, "platformBilling": "Annual"}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into public.kv_store (key, value) values
  ('muniUser:1', '{"id": 1, "muniId": 1, "name": "Andrea Powell", "email": "andrea.powell@kmc.gov.jm", "phone": "876-922-0140", "role": "CEO", "permissions": {"view": true, "payment": true, "review": true, "approve": true, "manageUsers": true}, "status": "Active", "created": "2026-01-14"}'::jsonb),
  ('muniUser:2', '{"id": 2, "muniId": 1, "name": "Paul Bennett", "email": "paul.bennett@kmc.gov.jm", "phone": "876-922-0141", "role": "Accountant", "permissions": {"view": true, "payment": true, "review": false, "approve": false, "manageUsers": false}, "status": "Active", "created": "2026-01-20"}'::jsonb),
  ('muniUser:3', '{"id": 3, "muniId": 1, "name": "Sasha Grant", "email": "sasha.grant@kmc.gov.jm", "phone": "876-922-0142", "role": "Supervisor", "permissions": {"view": true, "payment": false, "review": true, "approve": false, "manageUsers": false}, "status": "Active", "created": "2026-01-20"}'::jsonb),
  ('muniUser:4', '{"id": 4, "muniId": 4, "name": "Marlon Reid", "email": "marlon.reid@stmary.gov.jm", "phone": "876-465-2210", "role": "CEO", "permissions": {"view": true, "payment": true, "review": true, "approve": true, "manageUsers": true}, "status": "Active", "created": "2026-02-02"}'::jsonb),
  ('muniUser:5', '{"id": 5, "muniId": 4, "name": "Tanya Ford", "email": "tanya.ford@stmary.gov.jm", "phone": "876-465-2211", "role": "Accountant", "permissions": {"view": true, "payment": true, "review": false, "approve": false, "manageUsers": false}, "status": "Active", "created": "2026-02-05"}'::jsonb),
  ('muniUser:6', '{"id": 6, "muniId": 4, "name": "Richard Dunn", "email": "richard.dunn@stmary.gov.jm", "phone": "876-465-2212", "role": "Supervisor", "permissions": {"view": true, "payment": false, "review": true, "approve": false, "manageUsers": false}, "status": "Active", "created": "2026-02-05"}'::jsonb),
  ('muniUser:7', '{"id": 7, "muniId": 7, "name": "Kerry-Ann Blake", "email": "kerryann.blake@mobay.gov.jm", "phone": "876-952-1873", "role": "CEO", "permissions": {"view": true, "payment": true, "review": true, "approve": true, "manageUsers": true}, "status": "Active", "created": "2026-03-10"}'::jsonb),
  ('muniUser:8', '{"id": 8, "muniId": 7, "name": "Odain Clarke", "email": "odain.clarke@mobay.gov.jm", "phone": "876-952-1874", "role": "Accountant", "permissions": {"view": true, "payment": true, "review": false, "approve": false, "manageUsers": false}, "status": "Active", "created": "2026-03-12"}'::jsonb),
  ('muniUser:9', '{"id": 9, "muniId": 7, "name": "Michelle Barrett", "email": "michelle.barrett@mobay.gov.jm", "phone": "876-952-1875", "role": "Supervisor", "permissions": {"view": true, "payment": false, "review": true, "approve": false, "manageUsers": false}, "status": "Active", "created": "2026-03-12"}'::jsonb),
  ('muniUser:10', '{"id": 10, "muniId": 11, "name": "Devon Hylton", "email": "devon.hylton@manchester.gov.jm", "phone": "876-962-4405", "role": "CEO", "permissions": {"view": true, "payment": true, "review": true, "approve": true, "manageUsers": true}, "status": "Active", "created": "2026-04-22"}'::jsonb),
  ('muniUser:11', '{"id": 11, "muniId": 11, "name": "Sherika Palmer", "email": "sherika.palmer@manchester.gov.jm", "phone": "876-962-4406", "role": "Accountant", "permissions": {"view": true, "payment": true, "review": false, "approve": false, "manageUsers": false}, "status": "Active", "created": "2026-04-24"}'::jsonb),
  ('muniUser:12', '{"id": 12, "muniId": 11, "name": "Andre Lawson", "email": "andre.lawson@manchester.gov.jm", "phone": "876-962-4407", "role": "Supervisor", "permissions": {"view": true, "payment": false, "review": true, "approve": false, "manageUsers": false}, "status": "Active", "created": "2026-04-24"}'::jsonb),
  ('muniUser:13', '{"id": 13, "muniId": 14, "name": "Sasha-Kay Reid", "email": "portmore.admin@gov.jm", "phone": "876-988-7300", "role": "CEO", "permissions": {"view": true, "payment": true, "review": true, "approve": true, "manageUsers": true}, "status": "Active", "created": "2026-08-01"}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into public.kv_store (key, value) values ('platform:agenciesSeeded', 'true'::jsonb)
on conflict (key) do nothing;
insert into public.kv_store (key, value) values ('platform:muniUsersSeeded', 'true'::jsonb)
on conflict (key) do nothing;

-- Role permission templates (ADMIN_ROLE_SEED), demo venues (`venues`), the
-- default per-municipality advertisement price list (`adItems`, built from
-- DEFAULT_AD_TEMPLATE), and the one seeded watchlist entry — same reasoning
-- as above: the app's own client-side one-time seed for these can never
-- succeed under RLS (it requires an authenticated admin session at the
-- exact moment a page's top-level script runs, which in practice never
-- happens before the browser has finished restoring the session), so it's
-- loaded directly here instead.
insert into public.kv_store (key, value) values
  ('role:1', '{"id": 1, "name": "Full Access", "permissions": ["view_applications", "review_applications", "manage_venues", "manage_staff", "view_reports", "manage_fees"]}'::jsonb),
  ('role:2', '{"id": 2, "name": "Reviewer", "permissions": ["view_applications", "review_applications", "view_reports"]}'::jsonb),
  ('role:3', '{"id": 3, "name": "Read Only", "permissions": ["view_applications", "view_reports"]}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into public.kv_store (key, value) values
  ('venue:v1', '{"id": "v1", "muniId": 1, "name": "Ranny Williams Entertainment Centre", "active": true, "flagged": false, "flagReason": "", "streetNumber": "47", "streetName": "Martello Drive", "district": "", "cost": 5000, "maxCap": 5000, "maxParking": 500, "ownerName": "Kingston & St. Andrew Municipal Corporation", "ownerAddress": "12 Constant Spring Road", "ownerPhone": "876-922-0100", "createdBy": "Andrea Powell", "created": "2026-01-20"}'::jsonb),
  ('venue:v2', '{"id": "v2", "muniId": 1, "name": "National Indoor Sports Centre Grounds", "active": true, "flagged": false, "flagReason": "", "streetNumber": "13", "streetName": "Arthur Wint Drive", "district": "", "cost": 5000, "maxCap": 3000, "maxParking": 400, "ownerName": "Independence Park Ltd.", "ownerAddress": "13 Arthur Wint Drive", "ownerPhone": "876-929-4970", "createdBy": "Andrea Powell", "created": "2026-02-11"}'::jsonb),
  ('venue:v3', '{"id": "v3", "muniId": 4, "name": "Sunset Beach Resort", "active": true, "flagged": false, "flagReason": "", "streetNumber": "", "streetName": "Boscobel Main Road", "district": "", "cost": 0, "maxCap": 600, "maxParking": 150, "ownerName": "Michael Chin", "ownerAddress": "Boscobel Main Road, St. Mary", "ownerPhone": "876-465-7701", "createdBy": "Marlon Reid", "created": "2026-02-15"}'::jsonb),
  ('venue:v4', '{"id": "v4", "muniId": 4, "name": "Highgate Community Centre", "active": false, "flagged": false, "flagReason": "", "streetNumber": "5", "streetName": "Main Street", "district": "Highgate", "cost": 3000, "maxCap": 250, "maxParking": 40, "ownerName": "St. Mary Municipal Corporation", "ownerAddress": "Port Maria, St. Mary", "ownerPhone": "876-994-2201", "createdBy": "Richard Dunn", "created": "2026-03-02"}'::jsonb),
  ('venue:v5', '{"id": "v5", "muniId": 7, "name": "Montego Bay Convention Centre Grounds", "active": true, "flagged": false, "flagReason": "", "streetNumber": "1", "streetName": "Sunset Boulevard", "district": "", "cost": 5000, "maxCap": 2000, "maxParking": 300, "ownerName": "Montego Bay Convention Centre Ltd.", "ownerAddress": "Rose Hall, St. James", "ownerPhone": "876-953-7100", "createdBy": "Kerry-Ann Blake", "created": "2026-03-18"}'::jsonb),
  ('venue:v6', '{"id": "v6", "muniId": 7, "name": "Freeport Fishing Beach", "active": true, "flagged": true, "flagReason": "Erosion damage to seating area \u2014 awaiting NWA remediation before further bookings.", "streetNumber": "", "streetName": "Freeport Main Road", "district": "", "cost": 5000, "maxCap": 500, "maxParking": 80, "ownerName": "Freeport Fishermen''s Co-op", "ownerAddress": "Freeport, St. James", "ownerPhone": "876-940-1100", "createdBy": "Michelle Barrett", "created": "2026-04-05"}'::jsonb),
  ('venue:v7', '{"id": "v7", "muniId": 11, "name": "Coral Cove Community Center", "active": true, "flagged": false, "flagReason": "", "streetNumber": "3", "streetName": "Coral Cove Lane", "district": "", "cost": 0, "maxCap": 250, "maxParking": 60, "ownerName": "Coral Cove Community Center", "ownerAddress": "3 Coral Cove Lane, Manchester", "ownerPhone": "876-962-1120", "createdBy": "Devon Hylton", "created": "2026-04-22"}'::jsonb),
  ('venue:v8', '{"id": "v8", "muniId": 11, "name": "May Day Mountain Grounds", "active": true, "flagged": false, "flagReason": "", "streetNumber": "", "streetName": "May Day Road", "district": "May Day", "cost": 5000, "maxCap": 800, "maxParking": 120, "ownerName": "Manchester Municipal Corporation", "ownerAddress": "Mandeville, Manchester", "ownerPhone": "876-962-4400", "createdBy": "Andre Lawson", "created": "2026-05-10"}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into public.kv_store (key, value) values
  ('adItem:ad-1-0', '{"id": "ad-1-0", "muniId": 1, "category": "Banners", "name": "Banners", "cost": 1500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-1', '{"id": "ad-1-1", "muniId": 1, "category": "Banners", "name": "Poster/Flyer", "cost": 500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-2', '{"id": "ad-1-2", "muniId": 1, "category": "Sign Boards", "name": "Sign Boards - 2x2", "cost": 1000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-3', '{"id": "ad-1-3", "muniId": 1, "category": "Sign Boards", "name": "Sign Boards - 3x3", "cost": 1500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-4', '{"id": "ad-1-4", "muniId": 1, "category": "Sign Boards", "name": "Sign Boards - 4x4", "cost": 2000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-5', '{"id": "ad-1-5", "muniId": 1, "category": "Sign Boards", "name": "Sign Boards - 8x4", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-6', '{"id": "ad-1-6", "muniId": 1, "category": "Stages", "name": "Stage(s) - 20x24", "cost": 8000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-7', '{"id": "ad-1-7", "muniId": 1, "category": "Stages", "name": "Stage(s) - 16x8", "cost": 6000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-8', '{"id": "ad-1-8", "muniId": 1, "category": "Stages", "name": "Stage(s) - 10x10", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-9', '{"id": "ad-1-9", "muniId": 1, "category": "Stages", "name": "Stage(s) - 8x8", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-10', '{"id": "ad-1-10", "muniId": 1, "category": "Stages", "name": "Stage(s) - 12x8", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-11', '{"id": "ad-1-11", "muniId": 1, "category": "Stages", "name": "Stage(s) - 12x12", "cost": 5000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-12', '{"id": "ad-1-12", "muniId": 1, "category": "Tents", "name": "Tents - 20x20", "cost": 6000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-13', '{"id": "ad-1-13", "muniId": 1, "category": "Tents", "name": "Tents - 10x20", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-14', '{"id": "ad-1-14", "muniId": 1, "category": "Tents", "name": "Tents - 10x10", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-1-15', '{"id": "ad-1-15", "muniId": 1, "category": "Other", "name": "Other structure", "cost": 2000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-0', '{"id": "ad-4-0", "muniId": 4, "category": "Banners", "name": "Banners", "cost": 1500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-1', '{"id": "ad-4-1", "muniId": 4, "category": "Banners", "name": "Poster/Flyer", "cost": 500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-2', '{"id": "ad-4-2", "muniId": 4, "category": "Sign Boards", "name": "Sign Boards - 2x2", "cost": 1000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-3', '{"id": "ad-4-3", "muniId": 4, "category": "Sign Boards", "name": "Sign Boards - 3x3", "cost": 1500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-4', '{"id": "ad-4-4", "muniId": 4, "category": "Sign Boards", "name": "Sign Boards - 4x4", "cost": 2000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-5', '{"id": "ad-4-5", "muniId": 4, "category": "Sign Boards", "name": "Sign Boards - 8x4", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-6', '{"id": "ad-4-6", "muniId": 4, "category": "Stages", "name": "Stage(s) - 20x24", "cost": 8000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-7', '{"id": "ad-4-7", "muniId": 4, "category": "Stages", "name": "Stage(s) - 16x8", "cost": 6000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-8', '{"id": "ad-4-8", "muniId": 4, "category": "Stages", "name": "Stage(s) - 10x10", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-9', '{"id": "ad-4-9", "muniId": 4, "category": "Stages", "name": "Stage(s) - 8x8", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-10', '{"id": "ad-4-10", "muniId": 4, "category": "Stages", "name": "Stage(s) - 12x8", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-11', '{"id": "ad-4-11", "muniId": 4, "category": "Stages", "name": "Stage(s) - 12x12", "cost": 5000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-12', '{"id": "ad-4-12", "muniId": 4, "category": "Tents", "name": "Tents - 20x20", "cost": 6000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-13', '{"id": "ad-4-13", "muniId": 4, "category": "Tents", "name": "Tents - 10x20", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-14', '{"id": "ad-4-14", "muniId": 4, "category": "Tents", "name": "Tents - 10x10", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-4-15', '{"id": "ad-4-15", "muniId": 4, "category": "Other", "name": "Other structure", "cost": 2000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-0', '{"id": "ad-7-0", "muniId": 7, "category": "Banners", "name": "Banners", "cost": 1500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-1', '{"id": "ad-7-1", "muniId": 7, "category": "Banners", "name": "Poster/Flyer", "cost": 500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-2', '{"id": "ad-7-2", "muniId": 7, "category": "Sign Boards", "name": "Sign Boards - 2x2", "cost": 1000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-3', '{"id": "ad-7-3", "muniId": 7, "category": "Sign Boards", "name": "Sign Boards - 3x3", "cost": 1500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-4', '{"id": "ad-7-4", "muniId": 7, "category": "Sign Boards", "name": "Sign Boards - 4x4", "cost": 2000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-5', '{"id": "ad-7-5", "muniId": 7, "category": "Sign Boards", "name": "Sign Boards - 8x4", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-6', '{"id": "ad-7-6", "muniId": 7, "category": "Stages", "name": "Stage(s) - 20x24", "cost": 8000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-7', '{"id": "ad-7-7", "muniId": 7, "category": "Stages", "name": "Stage(s) - 16x8", "cost": 6000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-8', '{"id": "ad-7-8", "muniId": 7, "category": "Stages", "name": "Stage(s) - 10x10", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-9', '{"id": "ad-7-9", "muniId": 7, "category": "Stages", "name": "Stage(s) - 8x8", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-10', '{"id": "ad-7-10", "muniId": 7, "category": "Stages", "name": "Stage(s) - 12x8", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-11', '{"id": "ad-7-11", "muniId": 7, "category": "Stages", "name": "Stage(s) - 12x12", "cost": 5000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-12', '{"id": "ad-7-12", "muniId": 7, "category": "Tents", "name": "Tents - 20x20", "cost": 6000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-13', '{"id": "ad-7-13", "muniId": 7, "category": "Tents", "name": "Tents - 10x20", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-14', '{"id": "ad-7-14", "muniId": 7, "category": "Tents", "name": "Tents - 10x10", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-7-15', '{"id": "ad-7-15", "muniId": 7, "category": "Other", "name": "Other structure", "cost": 2000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-0', '{"id": "ad-11-0", "muniId": 11, "category": "Banners", "name": "Banners", "cost": 1500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-1', '{"id": "ad-11-1", "muniId": 11, "category": "Banners", "name": "Poster/Flyer", "cost": 500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-2', '{"id": "ad-11-2", "muniId": 11, "category": "Sign Boards", "name": "Sign Boards - 2x2", "cost": 1000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-3', '{"id": "ad-11-3", "muniId": 11, "category": "Sign Boards", "name": "Sign Boards - 3x3", "cost": 1500, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-4', '{"id": "ad-11-4", "muniId": 11, "category": "Sign Boards", "name": "Sign Boards - 4x4", "cost": 2000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-5', '{"id": "ad-11-5", "muniId": 11, "category": "Sign Boards", "name": "Sign Boards - 8x4", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-6', '{"id": "ad-11-6", "muniId": 11, "category": "Stages", "name": "Stage(s) - 20x24", "cost": 8000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-7', '{"id": "ad-11-7", "muniId": 11, "category": "Stages", "name": "Stage(s) - 16x8", "cost": 6000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-8', '{"id": "ad-11-8", "muniId": 11, "category": "Stages", "name": "Stage(s) - 10x10", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-9', '{"id": "ad-11-9", "muniId": 11, "category": "Stages", "name": "Stage(s) - 8x8", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-10', '{"id": "ad-11-10", "muniId": 11, "category": "Stages", "name": "Stage(s) - 12x8", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-11', '{"id": "ad-11-11", "muniId": 11, "category": "Stages", "name": "Stage(s) - 12x12", "cost": 5000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-12', '{"id": "ad-11-12", "muniId": 11, "category": "Tents", "name": "Tents - 20x20", "cost": 6000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-13', '{"id": "ad-11-13", "muniId": 11, "category": "Tents", "name": "Tents - 10x20", "cost": 4000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-14', '{"id": "ad-11-14", "muniId": 11, "category": "Tents", "name": "Tents - 10x10", "cost": 3000, "createdBy": "System", "created": "2026-01-01"}'::jsonb),
  ('adItem:ad-11-15', '{"id": "ad-11-15", "muniId": 11, "category": "Other", "name": "Other structure", "cost": 2000, "createdBy": "System", "created": "2026-01-01"}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into public.kv_store (key, value) values
  ('watchlist:556210987', '{"trn": "556210987", "muniId": 7, "fullName": "Kerry-Ann Fisher", "address": "8 Barnett Street, St. James", "phone": "876-410-7723", "email": "kfisher@gmail.com", "idFileName": "", "idFileData": null, "reason": "Submitted a Fire Certification that could not be verified with the JFB on a prior application.", "status": "Cleared", "flaggedBy": "Michelle Barrett", "flaggedDate": "2026-07-02", "clearedBy": "Kerry-Ann Blake", "clearedDate": "2026-07-20", "sourceAppNumber": "POA-072026-03"}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into public.kv_store (key, value) values ('platform:demoDataSeeded', 'true'::jsonb)
on conflict (key) do nothing;
insert into public.kv_store (key, value) values ('platform:rolesSeeded', 'true'::jsonb)
on conflict (key) do nothing;

-- The 7 already-seeded JCF officers (jcfdStaffUsers in atendify.html), keyed
-- jcfdUser:{branchId}:{id} so Row Level Security can scope each division's
-- own staff to key_part2 = atd_jcf_branch_id() (see phase1b_migration.sql
-- fix #8) the same way jcfBranch:{id}:signature already is.
insert into public.kv_store (key, value) values
  ('jcfdUser:5:1', '{"id": 1, "agencyId": 5, "name": "Insp. Rohan Blake", "email": "rohan.blake@jcf.gov.jm", "role": "Police Chief", "status": "Active"}'::jsonb),
  ('jcfdUser:5:2', '{"id": 2, "agencyId": 5, "name": "Sgt. Michelle Grant", "email": "michelle.grant@jcf.gov.jm", "role": "Police Supervisor", "status": "Active"}'::jsonb),
  ('jcfdUser:5:3', '{"id": 3, "agencyId": 5, "name": "Const. Andre Douglas", "email": "andre.douglas@jcf.gov.jm", "role": "Police Officer/Station", "status": "Active"}'::jsonb),
  ('jcfdUser:5:4', '{"id": 4, "agencyId": 5, "name": "Half Way Tree Station", "email": "hwt.station@jcf.gov.jm", "role": "Police Officer/Station", "status": "Active"}'::jsonb),
  ('jcfdUser:7:5', '{"id": 5, "agencyId": 7, "name": "Insp. Paula Grant", "email": "paula.grant@jcf.gov.jm", "role": "Police Chief", "status": "Active"}'::jsonb),
  ('jcfdUser:7:6', '{"id": 6, "agencyId": 7, "name": "Sgt. Kemar Wilson", "email": "kemar.wilson@jcf.gov.jm", "role": "Police Supervisor", "status": "Active"}'::jsonb),
  ('jcfdUser:7:7', '{"id": 7, "agencyId": 7, "name": "Port Maria Station", "email": "portmaria.station@jcf.gov.jm", "role": "Police Officer/Station", "status": "Active"}'::jsonb)
on conflict (key) do update set value = excluded.value;

insert into public.kv_store (key, value) values ('platform:jcfdUsersSeeded', 'true'::jsonb)
on conflict (key) do nothing;
