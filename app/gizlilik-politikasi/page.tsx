import { Metadata } from "next";
import Link from "next/link";

export const metadata: Metadata = {
    title: "Gizlilik Politikası | teqlif",
    description: "teqlif ilan ve açık artırma platformunun gizlilik politikası ve kişisel verilerin korunması hakkında bilgilendirme.",
};

export default function PrivacyPolicyPage() {
    return (
        <div className="container py-12" style={{ maxWidth: '800px' }}>
            <div className="bg-white p-8 md:p-12 rounded-2xl border border-[var(--border)] shadow-sm">
                <h1 className="text-3xl font-bold mb-8 text-[var(--text-primary)]">Gizlilik Politikası</h1>

                <div className="prose prose-teal max-w-none text-[var(--text-secondary)]" style={{ lineHeight: '1.8' }}>
                    <p className="mb-6"><strong>Son Güncelleme:</strong> 24 Şubat 2026</p>

                    <h2 className="text-xl font-bold mt-8 mb-4 text-[var(--text-primary)]">1. Giriş</h2>
                    <p className="mb-6">
                        teqlif ("biz", "bize" veya "bizim") olarak, gizliliğinize saygı duyuyor ve kişisel verilerinizi korumaya çok önem veriyoruz. Bu Gizlilik Politikası, teqlif mobil uygulamasını ve web platformunu kullandığınızda bilgilerinizi nasıl topladığımızı, kullandığımızı ve paylaştığımızı açıklamaktadır.
                    </p>

                    <h2 className="text-xl font-bold mt-8 mb-4 text-[var(--text-primary)]">2. Topladığımız Bilgiler</h2>
                    <p className="mb-4">Hizmetlerimizi kullanırken aşağıdaki kişisel veri türlerini toplayabiliriz:</p>
                    <ul className="list-disc pl-6 mb-6">
                        <li className="mb-2"><strong>Kayıt Bilgileri:</strong> Ad, soyad, e-posta adresi, telefon numarası.</li>
                        <li className="mb-2"><strong>İlan ve İçerik Bilgileri:</strong> Uygulamaya yüklediğiniz ilan detayları, ürün fotoğrafları ve kullanıcılar arası mesajlar.</li>
                        <li className="mb-2"><strong>Cihaz ve Kullanım Bilgileri:</strong> IP adresiniz, cihaz modeliniz, işletim sistemi sürümünüz ve uygulama içi etkileşimleriniz.</li>
                        <li className="mb-2"><strong>Konum Bilgileri:</strong> Etrafınızdaki ilanları gösterebilmek için cihazınızın konum verileri (sadece izniniz dâhilinde).</li>
                    </ul>

                    <h2 className="text-xl font-bold mt-8 mb-4 text-[var(--text-primary)]">3. Verilerin Kullanımı</h2>
                    <p className="mb-4">Topladığımız bilgileri aşağıdaki amaçlarla kullanırız:</p>
                    <ul className="list-disc pl-6 mb-6">
                        <li>Kullanıcı hesaplarını oluşturmak, doğrulamak ve yönetmek,</li>
                        <li>İlan verme, teklif sunma, açık artırma ve mesajlaşma gibi temel işlevleri sorunsuz bir şekilde yerine getirmek,</li>
                        <li>Müşteri desteği sunmak ve karşılaştığınız sorunları gidermek,</li>
                        <li>Platform güvenliğini sağlamak ve dolandırıcılık/spam faaliyetlerini engellemek,</li>
                        <li>Yasal yükümlülüklerimizi yerine getirmek.</li>
                    </ul>

                    <h2 className="text-xl font-bold mt-8 mb-4 text-[var(--text-primary)]">4. Bilgilerin Paylaşımı</h2>
                    <p className="mb-6">
                        Kişisel verilerinizi üçüncü şahıslara veya kurumlara satmıyoruz. Ancak, hizmetlerimizi sunabilmek (örneğin güvenli sunucu barındırma hizmetleri) veya yasal taleplere yanıt vermek amacıyla bilgilerinizi yetkili bulut servis sağlayıcılarıyla ve resmi kurumlarla paylaşabiliriz. İlan verdiğinizde, profil adınız ve ilan detaylarınız doğal olarak diğer kullanıcılara açıkça gösterilir.
                    </p>

                    <h2 className="text-xl font-bold mt-8 mb-4 text-[var(--text-primary)]">5. Veri Güvenliği</h2>
                    <p className="mb-6">
                        Kullanıcı verilerini yetkisiz erişime, veri sızıntılarına veya silinmeye karşı korumak için sektör standartlarında güvenlik ve şifreleme önlemleri alıyoruz. Tüm parola ve kimlik doğrulama işlemleri kriptografik yöntemlerle korunmaktadır.
                    </p>

                    <h2 className="text-xl font-bold mt-8 mb-4 text-[var(--text-primary)]">6. Haklarınız ve Veri Silme (Hesap Kapatma)</h2>
                    <p className="mb-6">
                        Hesap ayarlarınız üzerinden kişisel profil bilgilerinizi eksiksiz olarak görüntüleyebilir ve güncelleyebilirsiniz. Dilediğiniz zaman hesabınızın ve size ait tüm ilan, mesaj ve kişisel verilerin kalıcı olarak silinmesini talep etmek için uygulama içerisinden veya e-posta yoluyla bizimle iletişime geçebilirsiniz.
                    </p>

                    <h2 className="text-xl font-bold mt-8 mb-4 text-[var(--text-primary)]">7. İletişim</h2>
                    <p className="mb-6">
                        Bu Gizlilik Politikası, veri koruma uygulamalarımız veya kişisel verilerinizi silme talepleriniz ile ilgili her türlü sorunuz için bize ulaşabilirsiniz:<br /><br />
                        E-posta: <strong>destek@teqlif.com</strong>
                    </p>
                </div>
            </div>
        </div>
    );
}
