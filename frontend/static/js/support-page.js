    // Nav güncelle (giriş yapılmışsa kullanıcı adı)
    if (typeof Auth !== 'undefined') Auth.updateNav?.();

    // Accordion interaction logic
    document.addEventListener('DOMContentLoaded', () => {
        const accordionHeaders = document.querySelectorAll('.accordion-header');
        
        accordionHeaders.forEach(header => {
            header.addEventListener('click', function(e) {
                e.preventDefault(); // Varsayılan button davranışını engelle
                const item = this.parentElement;
                const content = item.querySelector('.accordion-content');
                
                if (item.classList.contains('active')) {
                    item.classList.remove('active');
                    content.style.maxHeight = null;
                } else {
                    item.classList.add('active');
                    content.style.maxHeight = content.scrollHeight + "px";
                }
            });
        });
    });
