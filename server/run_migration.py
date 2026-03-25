from app import app, sqlalchemy_db as db
from sqlalchemy import text

with app.app_context():
    print("Creating any fully missing tables...")
    db.create_all()
    
    queries = [
        "ALTER TABLE elder_profile ADD COLUMN step_total INT DEFAULT 0;",
        "ALTER TABLE elder_profile ADD COLUMN gawa_xp INT DEFAULT 0;",
        "ALTER TABLE elder_profile ADD COLUMN gawa_id INT DEFAULT NULL;",
        "ALTER TABLE elder_profile ADD COLUMN feed_starttime DATETIME DEFAULT NULL;",
        "ALTER TABLE gawa_appearance ADD COLUMN bonus DOUBLE DEFAULT 0.0;"
    ]
    
    for q in queries:
        try:
            db.session.execute(text(q))
            db.session.commit()
            print(f"Success: {q}")
        except Exception as e:
            db.session.rollback()
            print(f"Skipped (likely already exists): {q}")
            
    try:
        db.session.execute(text("ALTER TABLE elder_profile ADD CONSTRAINT fk_gawa_id FOREIGN KEY (gawa_id) REFERENCES gawa_appearance(gawa_id);"))
        db.session.commit()
        print("Success: Added FK constraint for gawa_id")
    except Exception as e:
        db.session.rollback()
        print("Skipped FK constraint (likely already exists)")

    print("Migration check complete.")
