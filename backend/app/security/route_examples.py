# Route Entegrasyon Örnekleri
# Güvenlik modüllerini mevcut route'lara nasıl entegre edeceğiniz

"""
Bu dosya, mevcut route'larınıza güvenlik modüllerini 
nasıl entegre edeceğinizi gösterir.
"""

# ==============================================================================
# ÖRNEK 1: Listing Router'a Güvenlik Ekleme
# ==============================================================================

"""
backend/app/routers/listings.py dosyasında:

from app.security.validation import SecureInputValidator, SecureTextField
from app.security.sanitizer import RouteInputValidator
from app.security.encryption import FieldEncryption

@router.post("/")
async def create_listing(
    listing: ListingCreate,
    db: AsyncSession = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # 1. Input validation
    data = listing.model_dump()
    valid, error = RouteInputValidator.validate_listing_input(data)
    if not valid:
        raise HTTPException(status_code=400, detail=error)
    
    # 2. XSS koruması - title ve description'ı temizle
    if data.get('description'):
        data['description'] = SecureTextField.escape_html(data['description'])
    
    # 3. Email gibi hassas alanları şifrele (opsiyonel)
    # Not: Bu, veritabanında şifrelenmiş olarak saklanır
    # Bütünleştirme için model katmanında yapılmalı
    
    # Devam...
"""

# ==============================================================================
# ÖRNEK 2: Auth Router'a Rate Limiting Ekleme
# ==============================================================================

"""
backend/app/routers/auth.py dosyasında:

from app.security.tokens import PasswordResetManager

@router.post("/change-password/send-code")
async def send_password_reset_code(
    email: str = Body(...),
    db: AsyncSession = Depends(get_db)
):
    # 1. Rate limiting kontrolü
    user = await db.scalar(select(User).where(User.email == email))
    if user:
        # Password reset attempts kontrolü
        allowed, error = await PasswordResetManager.check_reset_attempts(user.id)
        if not allowed:
            raise HTTPException(status_code=429, detail=error)
    
    # Devam...
"""

# ==============================================================================
# ÖRNEK 3: Search Endpoint SQL Injection Koruması
# ==============================================================================

"""
backend/app/routers/search.py dosyasında:

from app.security.sanitizer import sanitize_search_query, SQLInjectionProtection
from app.security.validation import SecureInputValidator

@router.get("")
async def search(
    q: str = Query(...),
    db: AsyncSession = Depends(get_db)
):
    # 1. SQL injection kontrolü
    if SQLInjectionProtection.has_sql(q):
        # Log suspicious activity
        security_logger.injection_attempt(client_ip, q)
        raise HTTPException(status_code=400, detail="Geçersiz arama")
    
    # 2. Search query sanitize et
    clean_query = sanitize_search_query(q)
    
    # Devam...
"""

# ==============================================================================
# ÖRNEK 4: Upload Router Dosya Güvenliği
# ==============================================================================

"""
backend/app/routers/upload.py dosyasında:

from app.security.validation import FileUploadSecurity
from app.security.encryption import SecureStorage

@router.post("/image")
async def upload_image(
    file: UploadFile = File(...),
    current_user: User = Depends(get_current_user)
):
    # 1. Dosya tipi kontrolü
    content_type = file.content_type
    valid, error = FileUploadSecurity.validate_type(content_type, "image")
    if not valid:
        raise HTTPException(status_code=400, detail=error)
    
    # 2. Dosya boyutu kontrolü
    contents = await file.read()
    valid, error = FileUploadSecurity.validate_file_size(len(contents), "image")
    if not valid:
        raise HTTPException(status_code=400, detail=error)
    
    # 3. Güvenli dosya adı oluştur
    safe_filename = SecureStorage.generate_secure_filename(file.filename)
    
    # Devam...
"""

# ==============================================================================
# KULLANIM
# ==============================================================================

"""
Route'lara güvenlik eklemek için:

1. İlgili router dosyasını açın
2. Gerekli import'ları ekleyin:
   - from app.security.validation import ...
   - from app.security.sanitizer import ...

3. Endpoint fonksiyonlarınızın başına validation ekleyin

4. Değişiklikleri kaydedin ve test edin

Not: Bu değişiklikler mevcut kodunuzu etkileyecektir.
Tüm testleri çalıştırdıktan sonra production'a alın.
"""

__all__ = []
