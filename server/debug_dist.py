from app import app
from models import ElderProfile, GawaAppearance, GetAppearanceList, db
import random

def test_distribute():
    with app.app_context():
        # Setup test data
        elder = ElderProfile.query.filter_by(elder_id='AAAA').first()
        if not elder:
            elder = ElderProfile(elder_id='AAAA', user_id=1, step_total=5000)
            db.session.add(elder)
            db.session.commit()
        else:
            elder.step_total = 5000
            db.session.commit()
            
        print(f"Initial: Elder {elder.elder_id}, step_total={elder.step_total}")
        
        # Simulate route logic
        elders = ElderProfile.query.filter(ElderProfile.elder_id.isnot(None)).all()
        appearances = GawaAppearance.query.all()
        if not appearances:
            db.session.add(GawaAppearance(gawa_name="Test Gawa", gawa_rarity="rare"))
            db.session.commit()
            appearances = GawaAppearance.query.all()
            
        now = datetime.utcnow()
        from datetime import timedelta
        endtime = now + timedelta(days=180)
        
        for e in elders:
            random_appearance = random.choice(appearances)
            current_steps = e.step_total or 0
            
            # Find EXISTING entry for this elder (ANY gawa)
            # The user's PK includes gawa_id, so filter_by(elder_id=e.elder_id) finds all.
            # Maybe there should only be one active?
            
            existing = GetAppearanceList.query.filter_by(elder_id=e.elder_id).first()
            if existing:
                print(f"Found existing for elder {e.elder_id}: Gawa {existing.gawa_id}, Size {existing.gawa_size}")
                # Update it
                existing.gawa_id = random_appearance.gawa_id
                existing.feed_starttime = now
                existing.feed_endtime = endtime
                existing.gawa_size = current_steps
            else:
                new_entry = GetAppearanceList(
                    elder_id=e.elder_id,
                    gawa_id=random_appearance.gawa_id,
                    feed_starttime=now,
                    feed_endtime=endtime,
                    gawa_size=current_steps
                )
                db.session.add(new_entry)
            
            e.step_total = 0
            
        db.session.commit()
        
        # Verify
        reloaded_elder = ElderProfile.query.get('AAAA')
        reloaded_entry = GetAppearanceList.query.filter_by(elder_id='AAAA').first()
        
        print(f"After Commit: Elder {reloaded_elder.elder_id}, step_total={reloaded_elder.step_total}")
        if reloaded_entry:
            print(f"After Commit: Entry Gawa {reloaded_entry.gawa_id}, Size {reloaded_entry.gawa_size}")
        else:
            print("After Commit: No entry found!")

if __name__ == "__main__":
    from datetime import datetime
    test_distribute()
