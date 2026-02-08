import random
import string

def generate_random_code(length=4):
    return ''.join(random.choices(string.digits, k=length))
