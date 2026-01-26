# Backend Fix for Call Access Verification

The issue is in the `verify_call_access` method. Here's the fix:

```python
@database_sync_to_async
def verify_call_access(self):
    """Verify user has access to this call"""
    try:
        # Remove 'call_' prefix if present for database lookup
        lookup_id = self.call_id.replace('call_', '') if self.call_id.startswith('call_') else self.call_id
        
        # First try to find by call_id (string format) - try both with and without prefix
        try:
            call = Call.objects.get(call_id=self.call_id)
        except Call.DoesNotExist:
            try:
                # Try without call_ prefix
                call = Call.objects.get(call_id=lookup_id)
            except Call.DoesNotExist:
                # Try with call_ prefix if it wasn't there
                prefixed_id = f"call_{lookup_id}"
                try:
                    call = Call.objects.get(call_id=prefixed_id)
                except Call.DoesNotExist:
                    # Finally try by numeric id
                    try:
                        call = Call.objects.get(id=int(lookup_id))
                    except (Call.DoesNotExist, ValueError):
                        logger.error(f"Call not found: {self.call_id}")
                        return False
        
        # Check if user is caller or receiver
        has_access = call.caller == self.user or call.receiver == self.user
        logger.info(f"Call access check for {self.user.id} on call {self.call_id}: {has_access}")
        return has_access
        
    except Exception as e:
        logger.error(f"Error in verify_call_access: {e}")
        return False
```

This fix handles all possible call ID formats and provides better error handling.